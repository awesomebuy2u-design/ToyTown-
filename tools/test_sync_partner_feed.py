import io
import json
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from unittest.mock import patch

from sync_partner_feed import main, parse_catalog

NOW = datetime(2026, 11, 27, 10, tzinfo=timezone.utc)
OFFER = ('<offer id="1001" available="true"><name>Іграшка</name>'
         '<url>https://shop.example/toy</url><price>125.99</price>'
         '<vendor>Maker</vendor><vendorCode>M-1</vendorCode></offer>')


def catalog(offers=OFFER, currency='<currencyID>UAH</currencyID>', date='2026-11-27 10:00'):
    return (f'<yml_catalog date="{date}"><shop>{currency}<offers>{offers}'
            '</offers></shop></yml_catalog>').encode()


class PartnerFeedTest(unittest.TestCase):
    def test_shop_currency_applies_unless_offer_overrides_it(self):
        foreign = OFFER.replace('1001', '1002').replace('</offer>', '<currencyId>EUR</currencyId></offer>')
        observed, result = parse_catalog(catalog(OFFER + foreign), NOW)
        self.assertEqual(observed, '2026-11-27T10:00:00+02:00')
        self.assertEqual([(row['source_id'], row['price'], row['model']) for row in result],
                         [('1001', 12599, 'M-1')])

    def test_rejects_stale_data_and_duplicate_offers(self):
        for document in (catalog(date='2026-11-25 10:00'), catalog(OFFER + OFFER)):
            with self.subTest(document=document), self.assertRaises(ValueError):
                parse_catalog(document, NOW)

    def test_rejects_doctype(self):
        with self.assertRaises(ValueError):
            parse_catalog(b'<!DOCTYPE yml_catalog>' + catalog(), NOW)

    def test_validation_mode_checks_the_export_without_importing(self):
        feeds = json.dumps([{'url': 'https://shop.example/export'}])
        with patch.dict('os.environ', {'TOYTOWN_PARTNER_FEEDS': feeds}, clear=True), \
             patch('sys.argv', ['sync_partner_feed.py', '--validate-only']), \
             patch('sync_partner_feed.download_catalog', return_value=parse_catalog(catalog(), NOW)) as download, \
             patch('sync_partner_feed.refresh') as refresh, redirect_stdout(io.StringIO()):
            self.assertEqual(main(), 0)
        download.assert_called_once()
        refresh.assert_not_called()


if __name__ == '__main__':
    unittest.main()
