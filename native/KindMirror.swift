import Cocoa
import AVFoundation
import CoreImage

final class Preview: NSView {
    var cameraLayer: AVCaptureVideoPreviewLayer?
    override func layout() { super.layout(); cameraLayer?.frame = bounds }
}

final class App: NSObject, NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let cameraQueue = DispatchQueue(label: "camera")
    let frameLock = NSLock()
    var latest: CVPixelBuffer?
    var devices: [AVCaptureDevice] = []
    var window: NSWindow!
    let preview = Preview()
    let picker = NSPopUpButton()
    let model = NSPopUpButton()
    let take = NSButton(title: "Take picture & compliment", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "Opening camera…")
    let words = NSTextField(wrappingLabelWithString: "A little kindness, just for you.")
    var request: URLSessionDataTask?
    var busy = false
    let context = CIContext(options: [.cacheIntermediates: false])

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:680,height:650), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        window.title = "Kind Mirror"; window.minSize = NSSize(width:480,height:540)
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 14; root.edgeInsets = NSEdgeInsets(top:18,left:18,bottom:18,right:18)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
        preview.wantsLayer = true; preview.layer?.backgroundColor = NSColor.black.cgColor
        let layer = AVCaptureVideoPreviewLayer(session:session); layer.videoGravity = .resizeAspect; preview.layer?.addSublayer(layer); preview.cameraLayer = layer
        root.addArrangedSubview(preview); preview.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-36).isActive = true; preview.heightAnchor.constraint(greaterThanOrEqualToConstant:260).isActive = true
        let row = NSStackView(); row.spacing = 10
        row.addArrangedSubview(NSTextField(labelWithString:"Camera:")); row.addArrangedSubview(picker)
        root.addArrangedSubview(row)
        picker.target = self; picker.action = #selector(changeCamera)
        let models = NSStackView(); models.spacing = 10
        models.addArrangedSubview(NSTextField(labelWithString:"Ollama:")); models.addArrangedSubview(model)
        model.addItem(withTitle:"gemma3:latest"); root.addArrangedSubview(models)
        take.target = self; take.action = #selector(snapshot); take.bezelStyle = .rounded; take.isEnabled = false; root.addArrangedSubview(take)
        status.font = .systemFont(ofSize:12); status.textColor = .secondaryLabelColor; root.addArrangedSubview(status)
        words.font = .systemFont(ofSize:19); words.alignment = .center; root.addArrangedSubview(words)
        words.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-36).isActive = true
        status.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-36).isActive = true
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        loadModels()
        AVCaptureDevice.requestAccess(for:.video) { allowed in DispatchQueue.main.async {
            guard allowed else { self.status.stringValue = "Allow Kind Mirror in System Settings → Privacy & Security → Camera, then reopen."; return }
            self.devices = AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.external,.continuityCamera],mediaType:.video,position:.unspecified).devices
            self.picker.removeAllItems(); self.picker.addItems(withTitles:self.devices.map{$0.localizedName})
            if self.devices.isEmpty { self.status.stringValue = "No camera found. Connect a camera and reopen the app." } else { self.changeCamera() }
        }}
    }
    func loadModels() {
        URLSession.shared.dataTask(with: URL(string:"http://127.0.0.1:11434/api/tags")!) { data,_,_ in
            guard let data, let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let list = object["models"] as? [[String:Any]] else { return }
            let names = list.compactMap{$0["name"] as? String}.filter{$0.hasPrefix("gemma3")}
            DispatchQueue.main.async { if !names.isEmpty { self.model.removeAllItems(); self.model.addItems(withTitles:names); self.model.selectItem(withTitle:"gemma3:latest") } }
        }.resume()
    }
    @objc func changeCamera() {
        guard devices.indices.contains(picker.indexOfSelectedItem) else { return }
        let device = devices[picker.indexOfSelectedItem]; take.isEnabled = false; picker.isEnabled = false
        status.stringValue = "Opening \(device.localizedName)…"
        cameraQueue.async {
            self.session.stopRunning(); self.session.beginConfiguration()
            self.session.inputs.forEach{self.session.removeInput($0)}
            self.session.outputs.forEach{self.session.removeOutput($0)}
            self.frameLock.lock(); self.latest = nil; self.frameLock.unlock()
            do {
                let input = try AVCaptureDeviceInput(device:device)
                guard self.session.canAddInput(input) else { throw NSError(domain:"Camera",code:1) }
                self.session.addInput(input); self.session.sessionPreset = .vga640x480
                let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue:self.cameraQueue)
                guard self.session.canAddOutput(output) else { throw NSError(domain:"Camera",code:2) }
                self.session.addOutput(output); self.session.commitConfiguration(); self.session.startRunning()
                DispatchQueue.main.async {self.status.stringValue = "Ready. Pictures stay in memory. Only the snapshot goes to local Ollama."; self.take.isEnabled = !self.busy; self.picker.isEnabled = true}
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status.stringValue = "Couldn’t open camera. Close other camera apps or select another camera."; self.picker.isEnabled = true }
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameLock.lock(); latest = CMSampleBufferGetImageBuffer(sampleBuffer); frameLock.unlock()
    }
    @objc func snapshot() {
        guard !busy else {return}
        frameLock.lock(); let buffer = latest; frameLock.unlock()
        guard let buffer else {status.stringValue = "Waiting for the first camera frame. Try again in a moment."; return}
        let image = CIImage(cvPixelBuffer:buffer)
        let scale = min(1,384 / max(image.extent.width,image.extent.height))
        guard let jpeg = context.jpegRepresentation(of:image.transformed(by:CGAffineTransform(scaleX:scale,y:scale)),colorSpace:CGColorSpaceCreateDeviceRGB(),options:[kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption:0.65]) else {return}
        busy = true; take.isEnabled = false; model.isEnabled = false
        status.stringValue = "Picture taken. Gemma is writing… You can still use the camera."
        words.stringValue = ""
        let selected = model.titleOfSelectedItem ?? "gemma3:latest"
        let prompt = "Give the person in this image one brief, kind compliment in 1–2 sentences. Address them as you. Mention only a visible detail like clothing or style. Do not infer personality, emotions, age, gender, health or ethnicity. No ratings or flirting. If no person is visible, say so gently."
        let body: [String:Any] = ["model":selected,"stream":false,"keep_alive":"5m","messages":[["role":"user","content":prompt,"images":[jpeg.base64EncodedString()]]],"options":["num_ctx":2048,"num_predict":60,"temperature":0.7]]
        var req = URLRequest(url:URL(string:"http://127.0.0.1:11434/api/chat")!); req.httpMethod = "POST"; req.timeoutInterval = 180; req.setValue("application/json",forHTTPHeaderField:"Content-Type"); req.httpBody = try? JSONSerialization.data(withJSONObject:body)
        let start = Date()
        request = URLSession.shared.dataTask(with:req) {data,response,error in
            let object = data.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
            let text = (object?["message"] as? [String:Any])?["content"] as? String
            DispatchQueue.main.async {
                self.busy = false; self.take.isEnabled = self.session.isRunning; self.model.isEnabled = true
                if let text, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    self.words.stringValue = text.trimmingCharacters(in:.whitespacesAndNewlines)
                    self.status.stringValue = "Ready for another picture. Last reply: \(Int(Date().timeIntervalSince(start))) seconds."
                } else {
                    self.status.stringValue = (object?["error"] as? String) ?? (error?.localizedDescription ?? "Ollama returned no words.")
                    self.words.stringValue = "Make sure Ollama is running with a vision-capable Gemma 3 model."
                }
                self.request = nil
            }
        }; request?.resume()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification:Notification) {request?.cancel(); session.stopRunning()}
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
