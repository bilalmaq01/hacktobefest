import http from 'node:http';
import { readFile } from 'node:fs/promises';
const port = Number(process.env.PORT || 3000);
const ollama = process.env.OLLAMA_HOST || 'http://127.0.0.1:11434';
let busy = false;
const prompt = `Write a warm, sincere compliment addressed directly to the person as "you", in two short sentences, under 55 words. No preamble, ratings, flirting, comparisons, or exaggerated praise. If an image is attached, mention one clearly visible positive detail such as clothing, colors, or styling. Do not infer personality, emotions, age, gender, health, ethnicity, or other sensitive traits from appearance. If nobody is visible, say you couldn't see someone and offer a kind general encouragement. Without an image, offer general encouragement without pretending to see the person.`;
const json = (res, status, body) => { res.writeHead(status, {'Content-Type':'application/json','Cache-Control':'no-store'}); res.end(JSON.stringify(body)); };
const server = http.createServer(async (req,res) => {
  try {
    if (req.method === 'GET' && req.url === '/api/models') {
      const response = await fetch(`${ollama}/api/tags`, {signal:AbortSignal.timeout(5000)});
      if (!response.ok) throw Error('Ollama is unavailable.');
      return json(res,200,await response.json());
    }
    if (req.method === 'POST' && req.url === '/api/compliment') {
      if (req.headers.origin && req.headers.origin !== `http://${req.headers.host}`) return json(res,403,{error:'Use the app from its local address.'});
      if (busy) return json(res,429,{error:'A compliment is already being written. Please wait.'});
      let body = '';
      for await (const chunk of req) { body += chunk; if (body.length > 600000) return json(res,413,{error:'The photo is too large.'}); }
      let input; try { input = JSON.parse(body); } catch { return json(res,400,{error:'Invalid request.'}); }
      if (typeof input.model !== 'string' || !input.model.trim() || (input.image && (typeof input.image !== 'string' || !/^[A-Za-z0-9+/=]+$/.test(input.image)))) return json(res,400,{error:'Choose a model and take a new snapshot.'});
      busy = true;
      try {
        const response = await fetch(`${ollama}/api/chat`, {method:'POST',headers:{'Content-Type':'application/json'},signal:AbortSignal.timeout(180000),body:JSON.stringify({model:input.model,stream:false,keep_alive:'30s',messages:[{role:'user',content:prompt,...(input.image ? {images:[input.image]} : {})}],options:{num_ctx:2048,num_predict:100,temperature:0.8}})});
        const result = await response.json();
        if (!response.ok) return json(res,502,{error:result.error || 'Ollama could not generate a compliment.'});
        if (!result.message?.content?.trim()) return json(res,502,{error:'The model returned no words. Try again.'});
        return json(res,200,{text:result.message.content.trim()});
      } finally { busy = false; }
    }
    if (req.method === 'GET') {
      const files = {'/':'index.html','/app.js':'app.js','/style.css':'style.css'};
      const file = files[req.url?.split('?')[0]];
      if (file) {res.writeHead(200,{'Content-Type':file.endsWith('js')?'text/javascript':file.endsWith('css')?'text/css':'text/html','Cache-Control':'no-store'});return res.end(await readFile(new URL(`./public/${file}`,import.meta.url)));}
    }
    json(res,404,{error:'Not found'});
  } catch (error) { json(res,503,{error:error.name === 'TimeoutError'?'Ollama took too long. Try a smaller model or text-only mode.':'Cannot reach Ollama. Start Ollama, then reconnect.'}); }
});
server.listen(port,'127.0.0.1',()=>console.log(`Kind Mirror is ready at http://localhost:${port}`));
