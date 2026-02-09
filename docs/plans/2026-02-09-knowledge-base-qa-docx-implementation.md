# Knowledge Base QA Rich Text + DOCX Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Support rich-text Q/A (including image markdown), sync Q/A to NeuAI via DOCX file upload, and allow DOCX import that is parsed server-side.

**Architecture:** Reuse existing dashboard ProseMirror editor (markdown in DB), keep separator as `------`, introduce backend DOCX builder/parser services, and add a dedicated `import_docx` endpoint under Q/A resources. Sync path switches from NeuAI text API to file API.

**Tech Stack:** Vue 3 + Vuex (existing Editor + MessageFormatter), Rails controllers/services, HTTParty NeuAI client, `rubyzip` + Nokogiri for DOCX zip/xml processing.

### Task 1: Add failing backend specs (DOCX sync + DOCX import parser)

**Files:**
- Modify: `spec/services/kbase/qa_sync_service_spec.rb`
- Create: `spec/services/kbase/qa_docx_builder_spec.rb`
- Create: `spec/services/kbase/qa_docx_import_service_spec.rb`
- Create: `spec/controllers/api/v1/accounts/knowledge_bases/qa_pairs_controller_spec.rb`

**Step 1: Write failing tests for sync using file API**

Expected:
- `Kbase::QaSyncService#sync!` calls `create_document_by_file` / `update_document_by_file`.
- Uses separator `------`.

**Step 2: Write failing tests for DOCX builder/parser**

Expected:
- Builder outputs valid `.docx` zip with `word/document.xml`.
- Import parser extracts multiple Q/A blocks split by `------`.

**Step 3: Write failing request spec for `import_docx`**

Expected:
- Accepts `.docx` upload and creates Q/A records.
- Rejects missing/non-docx files with 422/400.

### Task 2: Implement backend DOCX support

**Files:**
- Modify: `Gemfile`
- Modify: `app/services/kbase/neuai_client.rb`
- Modify: `app/services/kbase/qa_sync_service.rb`
- Modify: `app/controllers/api/v1/accounts/knowledge_bases/qa_pairs_controller.rb`
- Modify: `config/routes.rb`
- Create: `app/services/kbase/qa_docx_builder.rb`
- Create: `app/services/kbase/qa_docx_import_service.rb`

**Step 1: Add `rubyzip` dependency**

Run: `bundle add rubyzip`

**Step 2: Extend NeuAI client file APIs**

Add:
- Optional `separator` argument to `create_document_by_file`.
- New `update_document_by_file`.

**Step 3: Implement `Kbase::QaDocxBuilder`**

Output:
- Temp `.docx` with Q/A content in `Question:` + `Answer:` blocks.
- Blocks joined by `------`.

**Step 4: Implement `Kbase::QaDocxImportService`**

Input:
- Uploaded `.docx`.

Output:
- Parsed array of `{ question:, answer: }`.

**Step 5: Wire sync/import controller**

Add:
- `POST /qa_pairs/import_docx` action.
- File validations + record creation + response payload.

### Task 3: Implement frontend rich-text + docx import UX

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/QAPairList.vue`
- Modify: `app/javascript/dashboard/store/modules/knowledgeBases.js`
- Modify: `app/javascript/dashboard/api/knowledgeBases.js`
- Modify: `app/javascript/dashboard/i18n/locale/en/knowledgeBase.json`

**Step 1: Convert Q/A form fields to rich editor**

Use existing `dashboard/components-next/Editor/Editor.vue`.

**Step 2: Render Q/A with markdown formatter**

Use existing `MessageFormatter` + `v-dompurify-html`.

**Step 3: Add DOCX import button + hidden file input**

Behavior:
- Accept `.docx` only.
- Calls new Vuex action + API endpoint.
- Shows success/error alert.

**Step 4: Add format guidance text**

Include:
- `Question:` / `Answer:` structure.
- Separator `------`.
- Image via markdown URL syntax.

### Task 4: Verify

**Files:**
- Optional updates from test fixes only

**Step 1: Run targeted specs**

Run:
- `bundle exec rspec spec/services/kbase/qa_sync_service_spec.rb`
- `bundle exec rspec spec/services/kbase/qa_docx_builder_spec.rb`
- `bundle exec rspec spec/services/kbase/qa_docx_import_service_spec.rb`
- `bundle exec rspec spec/controllers/api/v1/accounts/knowledge_bases/qa_pairs_controller_spec.rb`

**Step 2: Run frontend tests/lint for touched files (if configured)**

Run:
- `pnpm eslint app/javascript/dashboard/routes/dashboard/knowledgeBase/components/QAPairList.vue app/javascript/dashboard/store/modules/knowledgeBases.js app/javascript/dashboard/api/knowledgeBases.js`

**Step 3: Confirm manual flow**

Checklist:
- Rich-text Q/A can add image markdown.
- DOCX import creates Q/A.
- Sync sends DOCX to NeuAI.
