import unittest,tempfile,json
from pathlib import Path
from sign_app import configuration
class SigningTests(unittest.TestCase):
 def test_missing_identity_never_falls_back_to_ad_hoc(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(FileNotFoundError): configuration(Path(d)/'missing.json')
 def test_rejects_ad_hoc_or_malformed_identity(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'signing.json'
   for identity in ['-','', 'not-a-certificate']:
    p.write_text(json.dumps({'identity':identity,'keychain':'/tmp/login.keychain-db'}))
    with self.assertRaises(ValueError): configuration(p)
 def test_preserves_pinned_certificate(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'signing.json';p.write_text(json.dumps({'identity':'A'*40,'keychain':'/test/login.keychain-db'}))
   self.assertEqual(configuration(p)['identity'],'A'*40)
if __name__=='__main__':unittest.main()
