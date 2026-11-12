import fs from 'node:fs';
import path from 'node:path';
const encoded=process.env.ONESTEP_KEYSTORE_BASE64;
if(!encoded){console.log('CI test signing only. Final installable APKs must be signed with the saved private release key.');process.exit(0);}
const password=process.env.ONESTEP_SIGNING_PASSWORD;
if(!password||/[\r\n]/.test(password)||!process.env.RUNNER_TEMP||!process.env.GITHUB_ENV)throw new Error('Incomplete private signing configuration');
const bytes=Buffer.from(encoded,'base64');
if(bytes.length<1000||bytes.length>65536)throw new Error('Invalid keystore size');
const file=path.join(process.env.RUNNER_TEMP,'onestep-release.p12');
fs.writeFileSync(file,bytes,{mode:0o600});
console.log('::add-mask::'+password);
fs.appendFileSync(process.env.GITHUB_ENV,`ONESTEP_KEYSTORE=${file}\nONESTEP_STORE_PASSWORD=${password}\nONESTEP_KEY_PASSWORD=${password}\nONESTEP_KEY_ALIAS=onestep\n`);
console.log('Private signing configured. Only public certificate fingerprints may be printed.');
