import subprocess,tempfile,pathlib,secrets,json,os
run=lambda args,**kw: subprocess.run(args,check=True,**kw)
base=pathlib.Path.home()/'Library/Application Support/AlienPing';base.mkdir(parents=True,exist_ok=True)
config=base/'signing.json'
if config.exists():
 print('Existing signing configuration retained');raise SystemExit(0)
keychain=subprocess.check_output(['security','default-keychain','-d','user'],text=True).strip().strip('"')
with tempfile.TemporaryDirectory(prefix='alienping-sign-') as d:
 p=pathlib.Path(d);os.chmod(p,0o700)
 (p/'cert.conf').write_text('[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=ext\n[dn]\nCN=Psst Local Signing\n[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n')
 run(['/usr/bin/openssl','req','-new','-newkey','rsa:3072','-nodes','-x509','-sha256','-days','3650','-config',str(p/'cert.conf'),'-keyout',str(p/'key.pem'),'-out',str(p/'cert.pem')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 password=secrets.token_hex(24)
 env={**os.environ,'ALIENPING_P12_PASSWORD':password}
 run(['/usr/bin/openssl','pkcs12','-export','-inkey',str(p/'key.pem'),'-in',str(p/'cert.pem'),'-name','Psst Local Signing','-out',str(p/'identity.p12'),'-passout','env:ALIENPING_P12_PASSWORD'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 run(['security','import',str(p/'identity.p12'),'-k',keychain,'-P',password,'-T','/usr/bin/codesign'])
 cert=base/'signing-certificate.pem';cert.write_bytes((p/'cert.pem').read_bytes())
 fingerprint=subprocess.check_output(['/usr/bin/openssl','x509','-in',str(cert),'-noout','-fingerprint','-sha1'],text=True).strip().split('=')[1].replace(':','')
 config.write_text(json.dumps({'identity':fingerprint,'name':'Psst Local Signing','keychain':keychain},indent=2)+'\n');os.chmod(config,0o600)
 run(['security','add-trusted-cert','-r','trustRoot','-p','codeSign','-k',keychain,str(cert)])
 print('Persistent local code-signing identity created; private key imported into login keychain.')
