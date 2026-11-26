import base64
import copy
import io
import json
import os
import threading
import unittest
from http.server import ThreadingHTTPServer
from unittest.mock import patch
import urllib.error
import urllib.request

from modules import glass_ai_service as ai
from modules.sync_service import _SyncRequestHandler


def fixture():
    return {'unit': 'cm', 'row_count': 2, 'rows': [
        {'width_cm': 121.5, 'height_cm': 61, 'quantity': 4, 'reference': 'N4',
         'uncertain': False, 'note': '', 'source_text': '121,5 x 61 x4 N4'},
        {'width_cm': 87, 'height_cm': None, 'quantity': 2, 'reference': 'N3',
         'uncertain': True, 'note': 'Chiffre surchargé', 'source_text': '87 x ? x2 N3'},
    ], 'warnings': []}


class GlassAITests(unittest.TestCase):
    def setUp(self):
        self.config = {'api_key': 'synthetic-test-key', 'token': 'synthetic-pairing-code', 'model': ai.DEFAULT_MODEL}
        self.body = {'image_base64': base64.b64encode(b'\xff\xd8\xffsynthetic-jpeg').decode()}
        ai._CACHE.clear()

    def test_missing_configuration_and_auth_never_call_provider(self):
        for config, token, code in [({}, 'Bearer x', 'not_configured'),
                                     (self.config, 'Bearer wrong', 'unauthorized')]:
            with patch.object(ai, 'load_config', return_value=config), patch.object(ai, '_call_provider') as provider:
                with self.assertRaises(ai.GlassAIError) as raised:
                    ai.recognize(self.body, token)
                self.assertEqual(raised.exception.code, code)
                provider.assert_not_called()

    def test_nullable_values_are_preserved_and_marked_for_review(self):
        data = fixture(); data['rows'][1]['uncertain'] = False
        result = ai.validate_result(data)
        self.assertIsNone(result['rows'][1]['height_cm'])
        self.assertTrue(result['rows'][1]['uncertain'])
        self.assertEqual([r['reference'] for r in result['rows']], ['N4', 'N3'])

    def test_invalid_count_quantity_or_number_are_rejected(self):
        for field, value in [('row_count', 1), ('quantity', 2.5), ('width_cm', float('nan'))]:
            data = fixture()
            if field == 'row_count': data[field] = value
            else: data['rows'][0][field] = value
            with self.assertRaises(ai.GlassAIError): ai.validate_result(data)

    def test_two_calls_same_photo_use_one_request_and_do_not_merge_lines(self):
        data = fixture(); data['rows'][1] = copy.deepcopy(data['rows'][0])
        with patch.object(ai, 'load_config', return_value=self.config), patch.object(ai, '_call_provider', return_value=data) as provider:
            a = ai.recognize(self.body, 'Bearer synthetic-pairing-code')
            b = ai.recognize(self.body, 'Bearer synthetic-pairing-code')
            self.assertEqual(provider.call_count, 1)
            self.assertEqual(len(a['rows']), 2)
            self.assertEqual(a, b)

    def test_provider_receives_only_image_and_strict_schema(self):
        response = {'status': 'completed', 'output': [{'content': [{'type': 'output_text', 'text': json.dumps(fixture())}]}]}
        class Response(io.BytesIO): pass
        with patch.object(ai.urllib.request, 'urlopen', return_value=Response(json.dumps(response).encode())) as call:
            result = ai._call_provider(b'\xff\xd8\xfftest', self.config)
        request = call.call_args.args[0]
        payload = json.loads(request.data)
        self.assertEqual(request.full_url, 'https://api.openai.com/v1/responses')
        self.assertFalse(payload['store'])
        self.assertTrue(payload['text']['format']['strict'])
        self.assertEqual(payload['input'][0]['content'][1]['type'], 'input_image')
        self.assertEqual(result['row_count'], 2)
        self.assertNotIn('synthetic-test-key', json.dumps(payload))

    def test_provider_incomplete_response_is_not_presented_as_success(self):
        with patch.object(ai.urllib.request, 'urlopen', return_value=io.BytesIO(b'{"status":"incomplete"}')):
            with self.assertRaises(ai.GlassAIError): ai._call_provider(b'\xff\xd8\xfftest', self.config)

    def test_real_http_route_requires_token_then_returns_structured_rows(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), _SyncRequestHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        url = f'http://127.0.0.1:{server.server_port}/glass/recognize'
        try:
            with patch.object(ai, 'load_config', return_value=self.config), patch.object(ai, '_call_provider', return_value=fixture()) as provider:
                request = urllib.request.Request(url, json.dumps(self.body).encode(), {'Content-Type': 'application/json'})
                with self.assertRaises(urllib.error.HTTPError) as failure: urllib.request.urlopen(request)
                self.assertEqual(failure.exception.code, 401); provider.assert_not_called()
                request.add_header('Authorization', 'Bearer synthetic-pairing-code')
                with urllib.request.urlopen(request) as response:
                    self.assertEqual(json.load(response)['row_count'], 2)
                self.assertEqual(provider.call_count, 1)
        finally:
            server.shutdown(); server.server_close(); thread.join()

    @unittest.skipUnless(os.name == 'nt', 'DPAPI is Windows only')
    def test_windows_credential_roundtrip(self):
        value = b'synthetic key, no real credential'
        protected = ai._crypt(value)
        self.assertNotIn(value, protected)
        self.assertEqual(ai._crypt(protected, decrypt=True), value)

if __name__ == '__main__': unittest.main()
