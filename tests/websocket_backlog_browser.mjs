import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require('playwright');
const root=path.resolve(process.argv[2]);
const mime={'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.pck':'application/octet-stream'};
const server=http.createServer((req,res)=>{
 const name=new URL(req.url,'http://localhost').pathname;
 const file=path.join(root,name==='/'?'index.html':name);
 if (!file.startsWith(root)||!fs.existsSync(file)) {res.writeHead(404);res.end();return;}
 res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});
 fs.createReadStream(file).pipe(res);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
const lines=[];
try {
 browser=await chromium.launch({headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
 const page=await browser.newPage();
 page.on('console',msg=>{lines.push(msg.text());console.log(msg.text());});
 page.on('pageerror',e=>{lines.push('PAGE_ERROR '+e.message);console.log('PAGE_ERROR '+e.message);});
 await page.goto(`http://127.0.0.1:${server.address().port}/`);
 const deadline=Date.now()+20000;
 while(!lines.some(l=>/^WEBSOCKET_BACKLOG_TEST_/.test(l))&&Date.now()<deadline) await page.waitForTimeout(100);
 if(!lines.includes('WEBSOCKET_BACKLOG_TEST_OK')||lines.some(l=>/ERROR:|SCRIPT ERROR|Parse Error|PAGE_ERROR/.test(l))) throw new Error('bounded Web backlog or runtime-error gate failed');
 console.log('WEBSOCKET_BACKLOG_BROWSER_OK');
} catch(error) {console.log('WEBSOCKET_BACKLOG_BROWSER_FAILED '+error.message);process.exitCode=1;}
finally {if(browser) await browser.close();await new Promise(resolve=>server.close(resolve));}
