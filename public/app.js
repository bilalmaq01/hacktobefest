const $ = id => document.getElementById(id);
let stream, photo, busy = false, switching = false;
const stopTracks = () => { stream?.getTracks().forEach(track => track.stop()); stream = null; $('video').srcObject = null; $('video').hidden = true; $('live').hidden = true; $('stop').disabled = true; $('capture').disabled = true; if (!photo) $('placeholder').hidden = false; };
function ready() { $('generate').disabled = busy || !photo || !$('model').value; }
async function cameras() {
  const selected = stream?.getVideoTracks()[0]?.getSettings().deviceId;
  const devices = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === 'videoinput');
  $('camera').replaceChildren(...devices.map((d,i)=>new Option(d.label || `Camera ${i+1}`,d.deviceId)));
  if (selected) $('camera').value = selected;
  $('camera').disabled = devices.length === 0;
}
async function start(deviceId) {
  if (switching) return;
  switching = true; $('start').disabled = true; $('camera').disabled = true;
  stopTracks(); $('camera-status').textContent = 'Opening camera…';
  try {
    if (!navigator.mediaDevices?.getUserMedia) throw new Error('Camera access needs localhost and a supported browser.');
    stream = await navigator.mediaDevices.getUserMedia({audio:false,video:{...(deviceId ? {deviceId:{exact:deviceId}} : {}),width:{ideal:640},height:{ideal:480},frameRate:{ideal:15,max:15}}});
    $('video').srcObject = stream; await $('video').play();
    photo = null; $('snapshot').removeAttribute('src'); $('snapshot').hidden = true; $('retake').hidden = true;
    $('placeholder').hidden = true; $('video').hidden = false; $('live').hidden = false; $('capture').disabled = false; $('stop').disabled = false;
    await cameras(); $('camera-status').textContent = 'Ready whenever you are.';
  } catch(error) {
    stopTracks();
    $('camera-status').textContent = error.name === 'NotAllowedError' ? 'Camera permission is off. Allow camera access in your browser, then try again.' : error.name === 'NotFoundError' ? 'No camera found. Connect a camera and try again.' : `Couldn’t open this camera. ${error.message}`;
  } finally {switching = false; $('start').disabled = false; ready();}
}
$('start').onclick = () => start();
$('camera').onchange = () => start($('camera').value);
$('stop').onclick = () => {stopTracks(); $('camera-status').textContent='Camera is off.';};
$('capture').onclick = () => {
  const video = $('video'); if (!video.videoWidth) return;
  const canvas = document.createElement('canvas'); const scale = Math.min(1,512/Math.max(video.videoWidth,video.videoHeight));
  canvas.width = Math.round(video.videoWidth*scale); canvas.height = Math.round(video.videoHeight*scale);
  const ctx = canvas.getContext('2d'); ctx.translate(canvas.width,0); ctx.scale(-1,1); ctx.drawImage(video,0,0,canvas.width,canvas.height);
  photo = canvas.toDataURL('image/jpeg',0.75); $('snapshot').src=photo; $('snapshot').hidden=false; $('retake').hidden=false;
  stopTracks(); $('camera-status').textContent='Snapshot ready. Camera is off to save resources.'; ready();
};
$('retake').onclick = () => {photo=null;$('snapshot').removeAttribute('src');$('snapshot').hidden=true;$('retake').hidden=true;$('result').textContent='';ready();start($('camera').value);};
async function models() {
  $('refresh').disabled=true;
  try {
    const response = await fetch('/api/models'); const data = await response.json(); if (!response.ok) throw Error(data.error);
    const previous = $('model').value;
    $('model').replaceChildren(...data.models.map(m=>new Option(m.name,m.name)));
    const best = data.models.find(m=>m.name===previous) || data.models.find(m=>m.name.startsWith('gemma3')) || data.models[0];
    if (best) $('model').value=best.name;
    $('connection').textContent = best ? '● Ollama connected' : 'No models installed. Pull a model in Ollama.';
    window.localModels=data.models; modelMode();
  } catch { $('connection').textContent='Ollama is offline. Start it and reconnect.'; $('model').replaceChildren(new Option('No models available','')); }
  finally {$('refresh').disabled=false;ready();}
}
function modelMode() { const model=window.localModels?.find(m=>m.name===$('model').value); const supported=model?.capabilities; $('text-only').disabled=!!supported && !supported.includes('vision'); if ($('text-only').disabled) $('text-only').checked=true; ready(); }
$('model').onchange=modelMode; $('refresh').onclick=models;
$('generate').onclick = async () => {
  if(busy || !photo) return;
  busy=true; ready(); $('retake').disabled=true; $('model').disabled=true; $('text-only').disabled=true;
  $('generation-status').textContent='Finding the words… The first reply may take a little longer.'; $('result').textContent='';
  try {
    const response=await fetch('/api/compliment',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({model:$('model').value,...(!$('text-only').checked ? {image:photo.split(',')[1]} : {})})});
    const data=await response.json(); if(!response.ok) throw Error(data.error);
    $('note').hidden=true; $('note-help').hidden=true; $('result').textContent=data.text;
    $('generation-status').textContent=$('text-only').checked?'A little encouragement from your local model.':'Written by your local model, just for this moment.';
  } catch(error) {$('generation-status').textContent=`${error.message} You can retry, or choose text-only mode.`;}
  finally {busy=false; $('retake').disabled=false; $('model').disabled=false; modelMode();}
};
window.addEventListener('pagehide',stopTracks);
navigator.mediaDevices?.addEventListener('devicechange',()=>cameras().catch(()=>{}));
models();
