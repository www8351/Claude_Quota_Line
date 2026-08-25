# claude-quota-line

Two-line status line for Claude Code that shows the same numbers you see in the claude.ai usage panel, but inside the terminal, all the time.

```
Context win ██░░░░░░░░  22%             │ 5H Limit    █░░░░░░░░░  11% ↻ 4h48m
Weekly      ███░░░░░░░  28% ↻ Thu 12:59 │ Fable       ████░░░░░░  45% ↻ Thu 12:59
```

Bars turn green under 50%, yellow from 50%, red from 80%.

## What it shows

| Segment | Default label | Source | Meaning |
| --- | --- | --- | --- |
| Context | `Context win` | stdin | Context window fill for the current session |
| 5-hour | `5H Limit` | stdin, API fallback | Rolling 5-hour limit and time until it resets |
| Weekly | `Weekly` | stdin, API fallback | Weekly limit across all models and reset day |
| Per-model | `Fable` | API | Weekly limit for one model, configurable |

Every label is configurable, and all four are padded to the widest one so the bars line up.

## Requirements

* Windows PowerShell 5.1 or PowerShell 7 (`pwsh`)
* Claude Code 2.1.6 or newer
* A Pro or Max subscription. Rate limit data is not passed for API-key sessions.

## Install

```powershell
git clone https://github.com/www8351/Claude_Quota_Line
cd Claude_Quota_Line
.\install.ps1
```

Then restart Claude Code.

Options:

```powershell
.\install.ps1 -ModelKey opus -ModelLabel Opus   # track a different per-model bucket
.\install.ps1 -BarWidth 16                       # wider bars
.\install.ps1 -Ascii                             # no box-drawing characters
.\install.ps1 -Align left                        # default is right aligned
.\install.ps1 -Width 160                         # fixed width if auto-detect fails
.\install.ps1 -CtxLabel Ctx -FiveHourLabel 5h -WeekLabel Week   # shorter labels
.\install.ps1 -RefreshSeconds 600                # per-model cache lifetime
.\install.ps1 -Uninstall
```

The installer copies `statusline.ps1` to `~/.claude/quota-line/`, backs up `~/.claude/settings.json`, and merges a `statusLine` entry into it. Nothing else is touched.

## How it works

Claude Code runs the configured command after every turn and pipes a JSON payload to stdin. The script reads `context_window.used_percentage` and, when present, `rate_limits.five_hour` and `rate_limits.seven_day` (Claude Code adds these for Pro/Max after the first response of a session).

The per-model weekly figure is not part of that payload. For it, the script calls the usage endpoint that the `/usage` command itself uses, `https://api.anthropic.com/api/oauth/usage`, with the OAuth token from `~/.claude/.credentials.json`. This endpoint is undocumented and may change. The result is cached in `~/.claude/quota-line-cache.json` for 5 minutes (`-RefreshSeconds`). If the endpoint or the token is unavailable, that segment is simply dropped, the rest keeps working.

Right alignment pads each line to the detected terminal width, less `-RightMargin` (default 2). Detection tries the console API, `COLUMNS`, then `mode con`. If none works, lines stay left aligned; pass `-Width` to force a value. Note that `statusline.ps1` itself defaults to left alignment — the installer is what writes `-Align right` into the command.

To see the raw payload Claude Code sends, add `-DumpInput` to the command. The last payload is written to `~/.claude/quota-line-last-input.json`.

If a segment has no data, it is skipped rather than rendered empty. Right after `/clear` you may see the placeholder line until the first response arrives.

## Test

```powershell
.\test.ps1          # renders with a sample payload
.\test.ps1 -NoApi   # same, without the per-model API call
```

`quota.json` in this repo is a sample of the `statusLine` block the installer merges into
`~/.claude/settings.json`; the path inside it is one machine's and is not read by anything.

## License

MIT

---

# claude-quota-line

שורת סטטוס בשתי שורות לקלוד קוד שמציגה את אותם המספרים שמופיעים בחלון השימוש באתר, אבל בתוך הטרמינל, כל הזמן.

```
Context win ██░░░░░░░░  22%             │ 5H Limit    █░░░░░░░░░  11% ↻ 4h48m
Weekly      ███░░░░░░░  28% ↻ Thu 12:59 │ Fable       ████░░░░░░  45% ↻ Thu 12:59
```

הפסים ירוקים מתחת ל 50 אחוז, צהובים מ 50, אדומים מ 80.

## מה מוצג

* חלון ההקשר של הסשן הנוכחי.
* מגבלת חמש השעות והזמן שנותר עד האיפוס.
* המגבלה השבועית לכל המודלים ויום האיפוס.
* המגבלה השבועית למודל אחד לבחירה.

## דרישות

* חלונות עם PowerShell 5.1 או PowerShell 7.
* קלוד קוד בגרסה 2.1.6 ומעלה.
* מנוי Pro או Max. נתוני המגבלות לא נשלחים בסשן שעובד עם מפתח API.

## התקנה

```powershell
git clone https://github.com/www8351/Claude_Quota_Line
cd Claude_Quota_Line
.\install.ps1
```

אחרי ההתקנה יש להפעיל מחדש את קלוד קוד.

אפשרויות:

```powershell
.\install.ps1 -ModelKey opus -ModelLabel Opus
.\install.ps1 -BarWidth 16
.\install.ps1 -Ascii
.\install.ps1 -Align left
.\install.ps1 -Width 160
.\install.ps1 -CtxLabel Ctx -FiveHourLabel 5h -WeekLabel Week
.\install.ps1 -RefreshSeconds 600
.\install.ps1 -Uninstall
```

ההתקנה מעתיקה את הסקריפט לתיקייה הבאה, מגבה את קובץ ההגדרות ומוסיפה אליו מפתח אחד בלבד:

`~/.claude/quota-line/`

## איך זה עובד

קלוד קוד מריץ את הפקודה המוגדרת אחרי כל תור ומעביר לה JSON דרך הקלט הסטנדרטי. הסקריפט קורא משם את אחוז חלון ההקשר ואת שני חלונות המגבלה כאשר הם קיימים.

הנתון השבועי למודל בודד לא נמצא באותו JSON. בשבילו הסקריפט פונה לאותה נקודת קצה שבה משתמשת הפקודה `/usage`, עם הטוקן שנשמר בקובץ ההרשאות של קלוד קוד. נקודת הקצה הזו לא מתועדת ועלולה להשתנות. התוצאה נשמרת במטמון לחמש דקות. אם הטוקן או השרת לא זמינים, החלק הזה פשוט לא מוצג והשאר ממשיך לעבוד.

היישור לימין מרפד כל שורה עד רוחב הטרמינל שזוהה. אם הזיהוי נכשל השורות נשארות משמאל, ואפשר לכפות רוחב עם `-Width`. כדי לראות מה קלוד קוד שולח בפועל, מוסיפים לפקודה `-DumpInput` והקלט האחרון נכתב לקובץ הבא:

`~/.claude/quota-line-last-input.json`

## בדיקה

```powershell
.\test.ps1
.\test.ps1 -NoApi
```

## רישיון

MIT