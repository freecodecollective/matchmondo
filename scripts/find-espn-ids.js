#!/usr/bin/env node
// Find ESPN athlete IDs for players missing them.
// Uses ESPN's athlete search within the FIFA World Cup league context.

const fs = require('fs');
const path = require('path');

const PLAYERS_PATH = path.join(__dirname, '..', 'data', 'players.js');
const DELAY_MS = 250;

async function searchESPN(name, team) {
    const encoded = encodeURIComponent(name);
    const url = `https://site.web.api.espn.com/apis/common/v3/search?query=${encoded}&limit=5&type=player&sport=soccer`;
    try {
        const resp = await fetch(url, { signal: AbortSignal.timeout(10000) });
        if (!resp.ok) return null;
        const data = await resp.json();
        const items = data.items || [];
        for (const item of items) {
            if (item.type === 'player' && item.id) {
                const norm = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
                const dn = norm(item.displayName || '');
                const sn = norm(name);
                if (dn === sn || dn.includes(sn) || sn.includes(dn)) {
                    return parseInt(item.id);
                }
            }
        }
        return null;
    } catch {
        return null;
    }
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
    const src = fs.readFileSync(PLAYERS_PATH, 'utf8');
    const start = src.indexOf('{');
    const content = src.slice(start).replace(/;\s*$/, '');
    const data = eval('(' + content + ')');
    const teams = Object.keys(data.teams);

    let found = 0, notFound = 0, skipped = 0, total = 0;

    for (const team of teams) {
        let teamFound = 0;
        for (const player of data.teams[team]) {
            total++;
            if (player.espnId) { skipped++; continue; }

            const id = await searchESPN(player.name, team);
            if (id) {
                player.espnId = id;
                teamFound++;
                found++;
            } else {
                notFound++;
            }
            await sleep(DELAY_MS);
        }
        if (teamFound > 0) {
            process.stdout.write(`\r  ${team}: +${teamFound} IDs found`);
        }
    }

    console.log(`\n\nDone: ${found} found, ${notFound} not found, ${skipped} already had ID, ${total} total`);

    const header = src.slice(0, src.indexOf('{'));
    const json = JSON.stringify(data, null, 2);
    fs.writeFileSync(PLAYERS_PATH, header + json + ';\n');
    console.log('Wrote updated players.js');
}

main().catch(console.error);
