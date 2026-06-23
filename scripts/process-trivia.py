#!/usr/bin/env python3
"""Process pending Claude tasks in data/trivia.json using the Anthropic API."""

import hashlib
import json
import os
import sys
import urllib.request

ANTHROPIC_API = "https://api.anthropic.com/v1/messages"
TRIVIA_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "trivia.json")

# The 10 non-English languages the iOS app ships. en is the base (the question's
# top-level fields), so it is NOT stored under translations.
LANGS = ["ar", "de", "es", "es-ES", "fr", "it", "ja", "ko", "pt-BR", "zh-Hans"]
LANG_NAMES = {
    "ar": "Modern Standard Arabic", "de": "German",
    "es": "Latin American Spanish", "es-ES": "Spain (Castilian) Spanish",
    "fr": "French", "it": "Italian", "ja": "Japanese", "ko": "Korean",
    "pt-BR": "Brazilian Portuguese", "zh-Hans": "Simplified Chinese",
}
# Cap translations per run so a single cron tick stays well-bounded; the backlog
# drains over consecutive runs.
MAX_TRANSLATIONS_PER_RUN = 5


def call_claude(prompt):
    payload = {
        "model": "claude-opus-4-8",
        "max_tokens": 16384,
        "messages": [{"role": "user", "content": prompt}],
    }
    req = urllib.request.Request(
        ANTHROPIC_API,
        data=json.dumps(payload).encode(),
        headers={
            "x-api-key": os.environ["ANTHROPIC_API_KEY"],
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        result = json.load(resp)
    return result["content"][0]["text"]


def build_task_prompt(trivia, tasks_desc):
    existing_ids = [q["id"] for q in trivia["questions"]]
    return f"""You are a trivia question editor for a football tournament app called "Football 2026".

The 2026 tournament is CURRENTLY IN PROGRESS. Your training data may be outdated about
ongoing match results, goal tallies, and records. When a task tells you something has
changed (e.g. "Messi is now the top scorer", "X scored today"), TRUST THAT AS GROUND
TRUTH — do not second-guess it or substitute your own (possibly stale) knowledge.

CRITICAL RULES:
- NEVER use "World Cup" or "FIFA" in any text — say "Football 2026" or "the tournament" instead
- Each question needs: id (unique kebab-case slug), category (one of: history, players, rules, teams, venues, records, culture), question, options (array of exactly 4 strings), answer (0-3 index of correct option), explanation
- When modifying a question, keep all 4 options distinct — no duplicates
- "Ronaldo" without qualification means Ronaldo Nazário (Brazil, 15 WC goals). Cristiano Ronaldo (Portugal) has 8 WC goals. Do NOT confuse them.

Existing question IDs (do NOT reuse): {json.dumps(existing_ids)}

TASKS TO PROCESS:
{tasks_desc}

Return ONLY a JSON object with this exact structure (no markdown, no explanation outside the JSON):
{{
  "processed_questions": [
    {{
      "action": "add" or "modify",
      "target_id": "question-id-to-modify (only for modify)",
      "question": {{
        "id": "unique-slug",
        "category": "category",
        "question": "The question text?",
        "options": ["A", "B", "C", "D"],
        "answer": 0,
        "explanation": "Why the answer is correct."
      }}
    }}
  ]
}}"""


def process_tasks(trivia):
    pending_global = [t for t in trivia.get("pendingTasks", []) if t.get("status") == "pending"]
    q_tasks = [(i, q) for i, q in enumerate(trivia["questions"]) if q.get("claudeTask")]

    if not pending_global and not q_tasks:
        return False

    tasks_desc = ""
    for t in pending_global:
        tasks_desc += f"- GLOBAL TASK: {t['text']}\n"
    for i, q in q_tasks:
        tasks_desc += f"- QUESTION TASK on #{q['id']} (\"{q['question']}\"): {q['claudeTask']}\n"
        tasks_desc += f"  Current question data: {json.dumps(q, ensure_ascii=False)}\n"

    print(f"Processing {len(pending_global)} global + {len(q_tasks)} per-question tasks...")
    response = call_claude(build_task_prompt(trivia, tasks_desc))

    start = response.find("{")
    end = response.rfind("}") + 1
    if start < 0 or end <= 0:
        print(f"ERROR: Could not parse JSON from response: {response[:200]}")
        return False

    result = json.loads(response[start:end])
    questions_by_id = {q["id"]: (i, q) for i, q in enumerate(trivia["questions"])}

    for item in result.get("processed_questions", []):
        q = item["question"]
        q["needsReview"] = True
        if "World Cup" in json.dumps(q) or "FIFA" in json.dumps(q):
            print(f"  SKIPPED {q['id']}: contains forbidden terms")
            continue
        if item["action"] == "modify" and item.get("target_id") in questions_by_id:
            idx, _ = questions_by_id[item["target_id"]]
            trivia["questions"][idx] = q
            print(f"  MODIFIED: {item['target_id']}")
        elif item["action"] == "add":
            if q["id"] not in questions_by_id:
                trivia["questions"].append(q)
                print(f"  ADDED: {q['id']}")

    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat()
    for t in pending_global:
        t["status"] = "done"
        t["completed"] = now
    for i, q in q_tasks:
        if "claudeTask" in trivia["questions"][i]:
            del trivia["questions"][i]["claudeTask"]

    return True


# ---------------------------------------------------------------------------
# Localization of published questions
#
# Only PUBLISHED questions (approved == true) are translated — that is the step
# that puts a question in front of users. A question is (re)translated when its
# English content changes: we store a hash of the source text alongside the
# translations, and re-translate whenever the current hash no longer matches.
# So: publish -> translate; unpublish/edit/republish -> hash differs -> retranslate;
# unpublish/republish unchanged -> hash matches -> skipped (no API call).
# ---------------------------------------------------------------------------

def source_hash(q):
    """Fingerprint of the translatable English content (order-sensitive)."""
    basis = " ".join([q["question"], *q["options"], q["explanation"]])
    return hashlib.sha256(basis.encode("utf-8")).hexdigest()[:16]


def needs_translation(q):
    if not q.get("approved"):
        return False
    tr = q.get("translations") or {}
    if q.get("i18nSourceHash") != source_hash(q):
        return True
    for lang in LANGS:
        t = tr.get(lang) or {}
        if not t.get("question") or not t.get("explanation"):
            return True
        if len(t.get("options") or []) != len(q["options"]):
            return True
    return False


def build_translation_prompt(q):
    lang_list = "\n".join(f"- {code} ({LANG_NAMES[code]})" for code in LANGS)
    source = {"question": q["question"], "options": q["options"], "explanation": q["explanation"]}
    return f"""You are localizing a published trivia question for a football tournament app called "Football 2026". Translate it from English into all of these languages, using these EXACT language codes as JSON keys:
{lang_list}

CRITICAL RULES:
- Translate the question, every option, and the explanation into each language.
- KEEP THE OPTIONS IN THE EXACT SAME ORDER and the SAME COUNT ({len(q['options'])} options). The correct-answer index depends on option order, so never reorder, add, merge, or drop options.
- Keep numbers, years, scores, and proper nouns (player/team/city names) accurate; transliterate names naturally for ar/ja/ko/zh-Hans but keep them recognizable.
- NEVER use "World Cup" or "FIFA" in any language — use "Football 2026" or the local equivalent of "the tournament".
- Produce natural, idiomatic, native-quality phrasing — not literal word-for-word translation.

English source:
{json.dumps(source, ensure_ascii=False)}

Return ONLY a JSON object (no markdown, no commentary) of this exact shape:
{{"translations": {{"ar": {{"question": "…", "options": ["…"], "explanation": "…"}}, "de": {{…}}, "…": {{…}} }}}}
Include all {len(LANGS)} languages."""


def _valid_translation(t, n_options):
    if not isinstance(t, dict):
        return False
    if not t.get("question") or not t.get("explanation"):
        return False
    opts = t.get("options")
    if not isinstance(opts, list) or len(opts) != n_options or any(not o for o in opts):
        return False
    if "FIFA" in json.dumps(t, ensure_ascii=False) or "World Cup" in json.dumps(t, ensure_ascii=False):
        return False
    return True


def translate_questions(trivia):
    todo = [q for q in trivia["questions"] if needs_translation(q)]
    if not todo:
        return False

    print(f"{len(todo)} published question(s) need (re)translation; doing up to {MAX_TRANSLATIONS_PER_RUN} this run.")
    changed = False
    for q in todo[:MAX_TRANSLATIONS_PER_RUN]:
        try:
            response = call_claude(build_translation_prompt(q))
            start, end = response.find("{"), response.rfind("}") + 1
            if start < 0 or end <= 0:
                print(f"  SKIPPED {q['id']}: no JSON in translation response")
                continue
            result = json.loads(response[start:end])
            trans = result.get("translations", {})
            n = len(q["options"])
            if not all(_valid_translation(trans.get(lang), n) for lang in LANGS):
                bad = [lang for lang in LANGS if not _valid_translation(trans.get(lang), n)]
                print(f"  SKIPPED {q['id']}: invalid/missing translations for {bad}")
                continue
            q["translations"] = {
                lang: {
                    "question": trans[lang]["question"],
                    "options": trans[lang]["options"],
                    "explanation": trans[lang]["explanation"],
                }
                for lang in LANGS
            }
            q["i18nSourceHash"] = source_hash(q)
            changed = True
            print(f"  TRANSLATED: {q['id']}")
        except Exception as e:  # noqa: BLE001 - keep the run alive for other questions
            print(f"  ERROR translating {q['id']}: {e}")

    if len(todo) > MAX_TRANSLATIONS_PER_RUN:
        print(f"  {len(todo) - MAX_TRANSLATIONS_PER_RUN} more await translation (next run).")
    return changed


def main():
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Missing ANTHROPIC_API_KEY, skipping.")
        sys.exit(0)

    with open(TRIVIA_PATH) as f:
        trivia = json.load(f)

    changed_tasks = process_tasks(trivia)
    changed_trans = translate_questions(trivia)

    if not (changed_tasks or changed_trans):
        print("No pending tasks and all published questions are translated.")
        return

    with open(TRIVIA_PATH, "w") as f:
        json.dump(trivia, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print("Updated data/trivia.json")


if __name__ == "__main__":
    main()
