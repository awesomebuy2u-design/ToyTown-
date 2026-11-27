// Runs entirely in an empty in-memory database; never connects to Supabase.
// Pass the installed @electric-sql/pglite/dist/index.js path as the argument.
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

if (!process.argv[2]) throw new Error('Pass the installed PGlite module path');
const { PGlite } = await import(pathToFileURL(resolve(process.argv[2])).href);
const { pgcrypto } = await import(new URL('./contrib/pgcrypto.js', pathToFileURL(resolve(process.argv[2]))));
const database = new PGlite({ extensions: { pgcrypto } });
const root = fileURLToPath(new URL('../', import.meta.url));
try {
  for (const path of [
    'test/sql/content_deletion_fixture.sql',
    'supabase/migrations/20261118120000_activate_family_exchange_agreements.sql',
    'supabase/migrations/20261118123000_agreement_lifecycle.sql',
    'supabase/migrations/20261119141924_public_family_shops.sql',
    'supabase/migrations/20261121170019_delete_own_content.sql',
    'supabase/migrations/20261123122152_family_shop_shelves_and_chat_clearing.sql',
  ]) await database.exec(await readFile(resolve(root, path), 'utf8'));
  for (const path of [
    'test/sql/delete_own_content.sql',
    'test/sql/public_family_shops.sql',
    'test/sql/shop_shelves.sql',
    'test/sql/clear_conversation.sql',
    'test/sql/guardian_fixture.sql',
    'supabase/migrations/20261124100000_hide_completed_agreements.sql',
    'supabase/migrations/20261127055516_toytown_1_0_16_guardian_marketplace.sql',
    'test/sql/guardian_marketplace.sql',
  ]) {
    try {
      const results = await database.exec(await readFile(resolve(root, path), 'utf8'));
      for (const result of results) for (const row of result.rows ?? []) {
        if (row.result) console.log(row.result);
      }
    } catch (error) {
      throw new Error(`${path}: ${error.message} ${error.where ?? ''}`);
    }
  }
} finally {
  await database.close();
}
