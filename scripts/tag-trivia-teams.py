#!/usr/bin/env python3
"""Tag trivia questions with related team names.

Scans question text, options, and explanation for team name references and
writes a `teams` array on each question. Idempotent — safe to re-run.
"""

import json
import re
from pathlib import Path

TRIVIA_PATH = Path(__file__).resolve().parent.parent / "data" / "trivia.json"

TEAMS = [
    "Algeria", "Argentina", "Australia", "Austria", "Belgium",
    "Bosnia and Herzegovina", "Brazil", "Cabo Verde", "Canada", "Colombia",
    "Congo DR", "Croatia", "Curaçao", "Côte d'Ivoire", "Czechia",
    "Ecuador", "Egypt", "England", "France", "Germany", "Ghana", "Haiti",
    "IR Iran", "Iraq", "Japan", "Jordan", "Korea Republic", "Mexico",
    "Morocco", "Netherlands", "New Zealand", "Norway", "Panama", "Paraguay",
    "Portugal", "Qatar", "Saudi Arabia", "Scotland", "Senegal",
    "South Africa", "Spain", "Sweden", "Switzerland", "Tunisia", "Türkiye",
    "USA", "Uruguay", "Uzbekistan",
]

ALIASES = {
    "United States": "USA", "US": "USA", "USMNT": "USA", "American": "USA",
    "America": "USA",
    "Holland": "Netherlands", "Dutch": "Netherlands",
    "Turkish": "Türkiye", "Turkey": "Türkiye",
    "Iranian": "IR Iran", "Iran": "IR Iran", "Persia": "IR Iran",
    "South Korean": "Korea Republic", "Korea": "Korea Republic",
    "Korean": "Korea Republic",
    "Ivory Coast": "Côte d'Ivoire",
    "DRC": "Congo DR", "DR Congo": "Congo DR",
    "Bosnian": "Bosnia and Herzegovina", "Bosnia": "Bosnia and Herzegovina",
    "Czech Republic": "Czechia", "Czech": "Czechia",
    "Cape Verde": "Cabo Verde",
    "Saudi": "Saudi Arabia",
    "Argentine": "Argentina", "Argentinian": "Argentina",
    "Belgian": "Belgium",
    "Brazilian": "Brazil",
    "Canadian": "Canada",
    "Colombian": "Colombia",
    "Croatian": "Croatia",
    "Ecuadorian": "Ecuador",
    "Egyptian": "Egypt",
    "English": "England",
    "French": "France",
    "German": "Germany", "West Germany": "Germany",
    "Ghanaian": "Ghana",
    "Haitian": "Haiti",
    "Iraqi": "Iraq",
    "Japanese": "Japan",
    "Jordanian": "Jordan",
    "Mexican": "Mexico",
    "Moroccan": "Morocco",
    "Norwegian": "Norway",
    "Panamanian": "Panama",
    "Paraguayan": "Paraguay",
    "Portuguese": "Portugal",
    "Qatari": "Qatar",
    "Scottish": "Scotland",
    "Senegalese": "Senegal",
    "Spanish": "Spain",
    "Swedish": "Sweden",
    "Swiss": "Switzerland",
    "Tunisian": "Tunisia",
    "Uruguayan": "Uruguay",
    "Algerian": "Algeria",
    "Austrian": "Austria",
    "Australian": "Australia",
    "New Zealander": "New Zealand",
    "Kiwi": "New Zealand",
    "Curaçaoan": "Curaçao",
    "Ivorian": "Côte d'Ivoire",
}

PLAYER_TEAMS = {
    "Messi": "Argentina", "Maradona": "Argentina", "Batistuta": "Argentina",
    "Di María": "Argentina", "Kempes": "Argentina",
    "Pelé": "Brazil", "Ronaldo Nazário": "Brazil", "Ronaldinho": "Brazil",
    "Neymar": "Brazil", "Cafu": "Brazil", "Garrincha": "Brazil",
    "Rivaldo": "Brazil", "Romário": "Brazil", "Zico": "Brazil",
    "Mbappé": "France", "Mbappe": "France", "Zidane": "France",
    "Platini": "France", "Fontaine": "France", "Deschamps": "France",
    "Dembélé": "France", "Henry": "France", "Griezmann": "France",
    "Kane": "England", "Lineker": "England", "Beckham": "England",
    "Charlton": "England", "Moore": "England", "Hurst": "England",
    "Rooney": "England",
    "Klose": "Germany", "Müller": "Germany", "Beckenbauer": "Germany",
    "Matthaus": "Germany", "Matthäus": "Germany", "Klinsmann": "Germany",
    "Rummenigge": "Germany", "Schweinsteiger": "Germany",
    "Cristiano Ronaldo": "Portugal", "Eusébio": "Portugal", "Eusebio": "Portugal",
    "Modric": "Croatia", "Modrić": "Croatia", "Davor Šuker": "Croatia",
    "Suker": "Croatia",
    "Haaland": "Norway",
    "Robben": "Netherlands", "Cruyff": "Netherlands", "Van Basten": "Netherlands",
    "Bergkamp": "Netherlands",
    "Xavi": "Spain", "Iniesta": "Spain", "Torres": "Spain",
    "Villa": "Spain", "Yamal": "Spain",
    "Balogun": "USA", "Pulisic": "USA", "Dempsey": "USA",
    "Donovan": "USA", "Howard": "USA",
    "Salah": "Egypt",
    "Mané": "Senegal", "Mane": "Senegal",
    "Son": "Korea Republic",
    "Lozano": "Mexico", "Márquez": "Mexico",
    "Suárez": "Uruguay", "Forlán": "Uruguay",
    "James Rodríguez": "Colombia", "Valderrama": "Colombia",
    "Cahill": "Australia",
}


def extract_teams(text):
    found = set()
    for team in TEAMS:
        if re.search(r'\b' + re.escape(team) + r'\b', text):
            found.add(team)
    for alias, canonical in ALIASES.items():
        if re.search(r'\b' + re.escape(alias) + r'\b', text):
            found.add(canonical)
    for player, team in PLAYER_TEAMS.items():
        if re.search(r'\b' + re.escape(player) + r'\b', text):
            found.add(team)
    return sorted(found)


def main():
    with open(TRIVIA_PATH) as f:
        trivia = json.load(f)

    tagged = 0
    for q in trivia["questions"]:
        searchable = " ".join([
            q["question"],
            " ".join(q["options"]),
            q["explanation"],
        ])
        teams = extract_teams(searchable)
        q["teams"] = teams
        if teams:
            tagged += 1

    with open(TRIVIA_PATH, "w") as f:
        json.dump(trivia, f, indent=2, ensure_ascii=False)
        f.write("\n")

    total = len(trivia["questions"])
    print(f"Tagged {tagged}/{total} questions with team references")
    print(f"{total - tagged} questions have no team reference (general trivia)")


if __name__ == "__main__":
    main()
