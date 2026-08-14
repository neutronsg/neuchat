# NeuAI `generate_contact_note` action

When `inputs.action` is `generate_contact_note`, the Dify workflow should send `inputs.query` to the LLM with a contact-note prompt. The query already contains existing contact notes and public customer/agent conversation history.

The flow should instruct the model to produce one concise CRM note, avoid repeating facts already present in the notes, and use only information in the supplied context. If there is no new supported information, return an empty string so NeuChat does not create a note.

Return plain note text without JSON, headings, or code fences through an existing NeuChat-recognized output field, preferably `answer` or `text`.
