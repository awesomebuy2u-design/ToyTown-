"""Import a registered shop's complete, authorized YML catalog using server credentials."""
import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener, urlopen
from xml.etree import ElementTree as ET
from zoneinfo import ZoneInfo

MAX_BYTES = 20 * 1024 * 1024


def currency(element):
    return (element.findtext('currencyId') or element.findtext('currencyID') or '').strip().upper()


def parse_catalog(content, now):
    if len(content) > MAX_BYTES:
        raise ValueError('Catalog exceeds 20 MiB')
    xml = content.decode('utf-8-sig')
    if '<!DOCTYPE' in xml.upper():
        raise ValueError('Catalog must not have a doctype')
    root = ET.fromstring(xml)
    if root.tag != 'yml_catalog':
        raise ValueError('Expected a YML catalog')
    observed = datetime.fromisoformat(root.get('date', ''))
    if observed.tzinfo is None:
        observed = observed.replace(tzinfo=ZoneInfo('Europe/Kyiv'))
    if not now - timedelta(hours=24) <= observed <= now:
        raise ValueError('The catalog is outside its 24-hour freshness window')
    shop = root.find('shop')
    if shop is None:
        raise ValueError('Catalog must contain a shop')
    shop_currency = currency(shop)
    records = []
    ids = set()
    for offer in shop.findall('./offers/offer'):
        if (currency(offer) or shop_currency) != 'UAH':
            continue
        source_id = (offer.get('id') or '').strip()
        brand = (offer.findtext('vendor') or '').strip()
        model = (offer.findtext('vendorCode') or offer.findtext('model') or '').strip()
        title = (offer.findtext('name') or offer.findtext('model') or '').strip()
        url = (offer.findtext('url') or '').strip()
        parsed = urlsplit(url)
        amount = Decimal(offer.findtext('price') or 'NaN') * 100
        available = (offer.get('available') or '').lower()
        if (not source_id or source_id in ids or not title or
            parsed.scheme != 'https' or not parsed.hostname or not parsed.path or
            parsed.username is not None or parsed.password is not None or parsed.port is not None or
            not amount.is_finite() or not 0 < amount <= 2147483647 or amount != int(amount) or
            available not in ('true', 'false')):
            raise ValueError('Invalid or duplicate UAH offer; previous catalog retained')
        ids.add(source_id)
        records.append(dict(source_id=source_id, title=title, url=url, brand=brand,
                            model=model, price=int(amount), available=available == 'true'))
    if not 1 <= len(records) <= 50000:
        raise ValueError('Expected 1–50,000 UAH offers')
    return observed.isoformat(), records


def download_catalog(feed):
    address = feed['url']
    if urlsplit(address).scheme != 'https':
        raise ValueError('HTTPS is required')
    # Fetch the supplier separately; ToyTown credentials go only to the RPC.
    with urlopen(address, timeout=45) as response:
        if urlsplit(response.geturl()).scheme != 'https':
            raise ValueError('Invalid feed redirect')
        observed, records = parse_catalog(response.read(MAX_BYTES + 1), datetime.now(timezone.utc))
    host = feed.get('offer_host')
    if host and any(urlsplit(offer['url']).hostname != host for offer in records):
        raise ValueError('An offer link uses an unexpected host')
    return observed, records


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def refresh(feed, api, key, observed, records):
    if urlsplit(api).scheme != 'https':
        raise ValueError('HTTPS is required')
    body = json.dumps(dict(target_store=feed['store_id'], observed_at=observed, offers=records)).encode()
    headers = {'Content-Type': 'application/json', 'apikey': key}
    if not key.startswith('sb_secret_'):
        headers['Authorization'] = 'Bearer ' + key
    request = Request(api.rstrip('/') + '/rest/v1/rpc/replace_partner_feed', data=body, headers=headers)
    with build_opener(NoRedirects()).open(request, timeout=90) as response:
        return int(json.load(response))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check-file', type=argparse.FileType('rb'), metavar='FILE',
                      help='Check a local YML export without contacting Supabase')
    mode.add_argument('--validate-only', action='store_true',
                      help='Check all configured exports without contacting Supabase')
    args = parser.parse_args()
    if args.check_file:
        with args.check_file:
            observed, records = parse_catalog(args.check_file.read(MAX_BYTES + 1),
                                               datetime.now(timezone.utc))
        print(f'{len(records)} UAH offers verified; catalog date: {observed}.')
        return 0

    failures = 0
    try:
        feeds = json.loads(os.environ['TOYTOWN_PARTNER_FEEDS'])
        if not isinstance(feeds, list) or not feeds or not all(isinstance(feed, dict) for feed in feeds):
            raise ValueError('Expected a nonempty catalog list')
    except (KeyError, ValueError):
        print('TOYTOWN_PARTNER_FEEDS must contain a nonempty JSON array of catalog objects.', file=sys.stderr)
        return 1
    for index, feed in enumerate(feeds, start=1):
        try:
            observed, records = download_catalog(feed)
            if args.validate_only:
                print(f'Catalog {index}: {len(records)} UAH offers verified; catalog date: {observed}.')
            else:
                count = refresh(feed, os.environ['SUPABASE_URL'], os.environ['TOYTOWN_PARTNER_IMPORT_KEY'],
                                observed, records)
                print(f'Catalog {index}: {count} offers refreshed.')
        except (ValueError, KeyError, OSError, ET.ParseError, InvalidOperation) as exc:
            # The exception text can contain partner credentials.
            print(f'Catalog {index} failed: {type(exc).__name__}', file=sys.stderr)
            failures += 1
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
