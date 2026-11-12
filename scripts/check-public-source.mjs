import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const blocked=[/sb_publishable_[A-Za-z0-9_-]{20,}/,/sb_secret_[A-Za-z0-9_-]{20,}/,/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/,/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/];
const skip=new Set(['.git','.dart_tool','.build','build','release','Pods','ephemeral','android','ios','windows','linux']);
const publicConfig=JSON.parse(fs.readFileSync(path.join(root,'config/service.json'),'utf8'));
if(!/^sb_publishable_[A-Za-z0-9_-]+$/.test(publicConfig.publishableKey)||!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(publicConfig.url))throw new Error('Invalid public service defaults');
const publicFiles=new Set(['config/service.json','OneStep/Account.swift','portable/lib/connection.dart']);
let checked=0;
function walk(directory){
  for(const entry of fs.readdirSync(directory,{withFileTypes:true})){
    if(skip.has(entry.name))continue;
    const file=path.join(directory,entry.name);
    if(entry.isDirectory()){walk(file);continue;}
    if(!/\.(swift|dart|mjs|json|ya?ml|sql|md|sh|ps1|plist|pbxproj|lock)$/.test(entry.name))continue;
    let content=fs.readFileSync(file,'utf8');checked++;
    if(publicFiles.has(path.relative(root,file).replaceAll('\\','/')))content=content.replaceAll(publicConfig.publishableKey,'APPROVED_PUBLIC_CLIENT_KEY');
    if(blocked.some(pattern=>pattern.test(content)))throw new Error(`Possible embedded project token/private key: ${path.relative(root,file)}. Contents withheld.`);
    if(/Owner-Enrollment|owner-bootstrap\.sql/.test(entry.name))throw new Error('Private enrollment material must stay outside the source tree');
  }
}
walk(root);
console.log(`PASS: scanned ${checked} source/config files; only approved public connection defaults; no privileged keys or JWTs.`);
