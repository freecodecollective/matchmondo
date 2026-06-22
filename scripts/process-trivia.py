#!/usr/bin/env python3
"""Process pending Claude tasks in data/trivia.json using the Anthropic API."""

import json
import os
import sys
import urllib.request

ANTHROPIC_API = "https://api.anthropic.com/v1/messages"
TRIVIA_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "trivia.json")


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

CRITICAL RULES:
- NEVER use "World Cup" or "FIFA" in any text — say "Football 2026" or "the tournament" instead
- Each question needs: id (unique kebab-case slug), category (one of: history, players, rules, teams, venues, records, culture), question, options (array of exactly 4 strings), answer (0-3 index of correct option), explanation

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


def main():
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Missing ANTHROPIC_API_KEY, skipping.")
        sys.exit(0)

    with open(TRIVIA_PATH) as f:
        trivia = json.load(f)

    if not process_tasks(trivia):
        print("No pending tasks.")
        return

    with open(TRIVIA_PATH, "w") as f:
        json.dump(trivia, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print("Updated data/trivia.json")


if __name__ == "__main__":
    main()
