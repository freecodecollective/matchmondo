#!/usr/bin/env node
// Bulk-enrich players.js with career data from ESPN bio endpoint.
// Fetches teamHistory for every player with an espnId, populates clubs field.
// Rate-limited to avoid hammering ESPN.

const fs = require('fs');
const path = require('path');

const PLAYERS_PATH = path.join(__dirname, '..', 'data', 'players.js');
const DELAY_MS = 200; // 200ms between requests

async function fetchBio(espnId) {
    const url = `https://site.web.api.espn.com/apis/common/v3/sports/soccer/fifa.world/athletes/${espnId}/bio`;
    try {
        const resp = await fetch(url, { signal: AbortSignal.timeout(10000) });
        if (!resp.ok) return null;
        const data = await resp.json();
        return data.teamHistory || null;
    } catch {
        return null;
    }
}

function teamHistoryToClubs(history) {
    if (!history || !history.length) return null;
    return history
        .filter(h => h.displayName && !h.displayName.includes('Unattached'))
        .map(h => ({
            team: h.displayName,
            years: h.seasons || '',
            country: null
        }));
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

    let enriched = 0, failed = 0, skipped = 0, total = 0;

    for (const team of teams) {
        for (const player of data.teams[team]) {
            total++;
            if (!player.espnId) { skipped++; continue; }
            if (player.clubs && player.clubs.length > 0) { skipped++; continue; }

            const history = await fetchBio(player.espnId);
            const clubs = teamHistoryToClubs(history);
            if (clubs && clubs.length > 0) {
                player.clubs = clubs;
                enriched++;
                process.stdout.write(`\r  ${team}: ${player.name} -> ${clubs.length} clubs`);
            } else {
                failed++;
            }
            await sleep(DELAY_MS);
        }
    }

    console.log(`\n\nDone: ${enriched} enriched, ${failed} failed, ${skipped} skipped, ${total} total`);

    // Write back
    const header = src.slice(0, src.indexOf('{'));
    const json = JSON.stringify(data, null, 2);
    fs.writeFileSync(PLAYERS_PATH, header + json + ';\n');
    console.log('Wrote updated players.js');
}

main().catch(console.error);
