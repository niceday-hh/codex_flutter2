import base64
import json
import unittest
from run_detail_benchmark import parse_measurements


class ReportTransportTest(unittest.TestCase):
    def test_numbered_chunks_reassemble_without_timing_loss(self):
        row = {'ui_us': list(range(300)), 'text': '正文'}
        raw = base64.b64encode(json.dumps(row).encode()).decode()
        parts = [raw[i:i + 600] for i in range(0, len(raw), 600)]
        log = '\n'.join(f'I/flutter (1): DETAIL_CHUNK:1:{i}:{len(parts)}:{part}' for i, part in reversed(list(enumerate(parts))))
        self.assertEqual(parse_measurements(log), [row])

    def test_missing_or_truncated_chunks_are_rejected(self):
        with self.assertRaises(AssertionError):
            parse_measurements('DETAIL_CHUNK:1:0:2:e30=')
        with self.assertRaises(Exception):
            parse_measurements('DETAIL_CHUNK:1:0:1:eyJ')
