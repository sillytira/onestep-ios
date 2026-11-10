// Dependency-free, opaque PNG. Drawn as a native asset, not a generated photo.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const n = 1024;
const raw = Buffer.alloc((n * 3 + 1) * n);
const segmentDistance = (x,y,ax,ay,bx,by) => {
  const t = Math.max(0,Math.min(1,((x-ax)*(bx-ax)+(y-ay)*(by-ay))/((bx-ax)**2+(by-ay)**2)));
  return Math.hypot(x-ax-t*(bx-ax),y-ay-t*(by-ay));
};
for (let y=0;y<n;y++) for (let x=0;x<n;x++) {
  const offset = y*(n*3+1)+1+x*3;
  const glow = Math.max(0,1-Math.hypot(x-220,y-160)/1100);
  let rgb = [9+16*glow,91+55*glow,91+47*glow];
  const ring = Math.abs(Math.hypot(x-512,y-512)-310);
  if (ring<13) rgb = [128,206,192];
  if (Math.min(segmentDistance(x,y,330,514,455,638),segmentDistance(x,y,455,638,704,382))<36) rgb=[248,248,231];
  for(let c=0;c<3;c++) raw[offset+c]=Math.round(rgb[c]);
}
function crc(buffer) { let c=0xffffffff; for(const v of buffer){c^=v;for(let k=0;k<8;k++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0; }
function chunk(type,data){ const t=Buffer.from(type);const len=Buffer.alloc(4);len.writeUInt32BE(data.length);const sum=Buffer.alloc(4);sum.writeUInt32BE(crc(Buffer.concat([t,data])));return Buffer.concat([len,t,data,sum]); }
const header=Buffer.alloc(13);header.writeUInt32BE(n);header.writeUInt32BE(n,4);header[8]=8;header[9]=2;
const png=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
fs.writeFileSync(path.join(root,'OneStep/Assets.xcassets/AppIcon.appiconset/AppIcon.png'),png);
console.log('Generated opaque 1024px app icon.');
