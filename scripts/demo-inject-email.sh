#!/usr/bin/env bash
# DEMO helper (untracked) — inject a clean, fresh UNREAD email straight into the
# Gmail INBOX so Workflow 3 classifies it live, bypassing Gmail's spam filter on
# fresh inbound mail. Default example is a job application → classifies "recruiting".
# Run this during recording; WF3 (active, IMAP IDLE) fires within a few seconds.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - "$@" <<'PY'
import imaplib, ssl, time, email.utils
def gv(k):
    for line in open('.env'):
        if line.startswith(k+'='):
            return line.split('=',1)[1].strip().strip('"').strip("'")

frm   = "Jordan Lee <jordan.lee.dev@gmail.com>"
to    = gv('IMAP_USER')
subj  = "Application for your Senior Backend Engineer role"
body  = ("Hi,\n\nI'd like to apply for the Senior Backend Engineer opening. I have 8 years "
         "building Go and Node services on Postgres, and led the payments rewrite at my current "
         "company. Resume and portfolio attached. Available to interview this week.\n\nThanks,\nJordan")

msg = (f"From: {frm}\r\nTo: {to}\r\nSubject: {subj}\r\n"
       f"Date: {email.utils.formatdate(localtime=True)}\r\n"
       f"Message-ID: <demo-{int(time.time())}@autostream>\r\n"
       f"Content-Type: text/plain; charset=utf-8\r\n\r\n{body}\r\n").encode()

M = imaplib.IMAP4_SSL(gv('IMAP_HOST'), int(gv('IMAP_PORT') or 993), ssl_context=ssl.create_default_context())
M.login(gv('IMAP_USER'), gv('IMAP_PASS'))
M.append('INBOX', '', imaplib.Time2Internaldate(time.time()), msg)   # arrives UNSEEN, fresh UID
M.select('INBOX')
print("✓ injected unread email into INBOX —", subj)
print("  UNSEEN now:", len(M.search(None,'UNSEEN')[0].split()))
print("  → WF3 should fire in a few seconds: watch n8n Executions + Slack + Supabase llm_calls")
M.logout()
PY
