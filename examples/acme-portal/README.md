# Example: Acme Portal

Pre-generated metadata for a fictional "Acme Portal" client. Use this to see what the skill produces — browse the files to understand the structure, or deploy it to a sandbox to test the full flow.

## What's included

```
unpackaged/
├── package.xml
├── aiResponseFormats/
│   ├── AcmePortalChoices_AcmePortal01.aiResponseFormat
│   ├── AcmePortalChoicesWithImages_AcmePortal01.aiResponseFormat
│   └── AcmePortalTimePicker_AcmePortal01.aiResponseFormat
└── aiSurfaces/
    └── AcmePortal_AcmePortal01.aiSurface
```

**3 response formats:**
- Text Choices — clickable text options (2-7 items)
- Choices with Images — product/service cards with thumbnails
- Time Picker — appointment/callback time selection (uses Slack Block Kit schema as a reference pattern — replace with your own time picker schema if your client uses a different format)

**1 custom surface** connecting them all, with instructions to keep responses brief and avoid formats for single-choice responses.

## Deploy to a sandbox

```bash
./deploy.sh <org-alias> <agent-bundle-name>
```

See the main [README](../../README.md) for how to find your agent bundle name.
