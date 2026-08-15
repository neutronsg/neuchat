# NeuAI `generate_contact_note` action

When `inputs.action` is `generate_contact_note`, pass `inputs.query` to the LLM using this structure:

```text
Existing contact notes:
{{existing_contact_notes}}

Conversation history:
{{conversation_history}}
```

Only agent-created notes are included in `existing_contact_notes`; previous NeuAI output is excluded to avoid
recursively amplifying stale AI content. Each note includes its UTC created and updated timestamps, note type,
and author. Each public incoming/outgoing message includes its sent timestamp in the conversation inbox timezone,
conversation ID, message ID, direction, sender role, and sender name.

The flow should instruct the model to produce one concise CRM note, avoid repeating facts already present in the
notes, and use only information in the supplied context. If there is no new supported information, return an empty
string so NeuChat does not create a note.

Return plain note text without JSON, headings, or code fences through an existing NeuChat-recognized output field, preferably `answer` or `text`.
