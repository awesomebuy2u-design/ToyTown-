"""Build the offline map gazetteer from a downloaded GeoNames UA.zip extract."""
import json
import re
import sys
from pathlib import Path
from zipfile import ZipFile

CODES = {'PPL', 'PPLA', 'PPLA2', 'PPLA3', 'PPLA4', 'PPLC', 'PPLG', 'PPLL'}
CYRILLIC = re.compile(r"[А-Яа-яІіЇїЄєҐґЁёЫыЭэЪъЬьІіЎўѣӳæ\s’ʼ'`‘.()-]+")
rows = []
with ZipFile(sys.argv[1]) as source:
    for line in source.read('UA.txt').decode().splitlines():
        record = line.split('\t')
        if record[6] != 'P' or record[7] not in CODES or record[8] != 'UA':
            continue
        aliases = {record[1], record[2]}
        aliases.update(name for name in record[3].split(',') if CYRILLIC.fullmatch(name))
        aliases = sorted(name for name in aliases if len(name) > 2 and not any(c.isdigit() for c in name))
        rows.append([int(record[0]), float(record[4]), float(record[5]),
                     0 if record[7] in ('PPLC', 'PPLA') else 1, aliases])
rows.sort(key=lambda row: row[0])
output = Path(__file__).resolve().parents[1] / 'assets/places/ukraine.json'
output.write_text(json.dumps(rows, ensure_ascii=False, separators=(',', ':')) + '\n')
print(f'{len(rows)} settlement centres written to {output}')
