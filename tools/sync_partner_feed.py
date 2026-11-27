"""Import a registered shop's complete, authorized YML catalog using server credentials."""
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from xml.etree import ElementTree as ET
from zoneinfo import ZoneInfo

MAX_BYTES = 20 * 1024 * 1024


def parse_catalog(content, now):
    if len(content) > MAX_BYTES or b'<!DOCTYPE' in content.upper():
        raise ValueError('Unsupported catalog size or doctype')
    root = ET.fromstring(content)
    if root.tag != 'yml_catalog':
        raise ValueError('Expected a YML catalog')
    observed = datetime.fromisoformat(root.get('date', ''))
    if observed.tzinfo is None:
        observed = observed.replace(tzinfo=ZoneInfo('Europe/Kyiv'))
    if not now - timedelta(hours=24) <= observed <= now:
        raise ValueError('The catalog is outside its 24-hour freshness window')
    records = []
    ids = set()
    for offer in root.findall('./shop/offers/offer'):
        if offer.findtext('currencyId') != 'UAH':
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


def refresh(feed, api, key):
    address = feed['url']
    if urlsplit(address).scheme != 'https' or urlsplit(api).scheme != 'https':
        raise ValueError('HTTPS is required')
    # Fetch the supplier separately; ToyTown credentials go only to the RPC.
    with urlopen(address, timeout=45) as response:
        if urlsplit(response.geturl()).scheme != 'https':
            raise ValueError('Invalid feed redirect')
        observed, records = parse_catalog(response.read(MAX_BYTES + 1), datetime.now(timezone.utc))
    body = json.dumps(dict(target_store=feed['store_id'], observed_at=observed, offers=records)).encode()
    headers = {'Content-Type': 'application/json', 'apikey': key}
    if not key.startswith('sb_secret_'):
        headers['Authorization'] = 'Bearer ' + key
    request = Request(api.rstrip('/') + '/rest/v1/rpc/replace_partner_feed', data=body, headers=headers)
    with urlopen(request, timeout=90) as response:
        return int(json.load(response))


def main():
    failures = 0
    feeds = json.loads(os.environ['TOYTOWN_PARTNER_FEEDS'])
    api, key = os.environ['SUPABASE_URL'], os.environ['TOYTOWN_PARTNER_IMPORT_KEY']
    for index, feed in enumerate(feeds, start=1):
        try:
            count = refresh(feed, api, key)
            print(f'Catalog {index}: {count} offers refreshed.')
        except (ValueError, KeyError, OSError, HTTPError, URLError, ET.ParseError, InvalidOperation) as exc:
            # URLs can contain partner credentials. Show only the error category.
            print(f'Catalog {index} failed: {type(exc).__name__}', file=sys.stderr)
            failures += 1
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
