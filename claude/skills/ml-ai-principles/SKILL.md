---
name: ML/AI Engineering Principles
description: Use when building ML/LLM features, pipelines, or evals — MLOps lifecycle, RAG, prompt-vs-finetune, fairness, evaluation
globs: ["**/*.py", "**/*.ipynb", "**/ml/**", "**/ai/**", "**/models/**", "**/training/**", "**/pipelines/**", "**/notebooks/**"]
---

# ML/AI Engineering Principles & Laws

## Fundamental ML Laws

### Bias-Variance Tradeoff
"You cannot minimize both bias (underfitting) and variance (overfitting) simultaneously."
- High bias: model too simple, misses patterns (underfitting)
- High variance: model too complex, memorizes noise (overfitting)
- Sweet spot: validated via cross-validation, not training accuracy
- **Application**: start simple (linear/tree), add complexity only when underfitting proven

### No Free Lunch Theorem (Wolpert)
"No algorithm is universally best across all problems."
- CatBoost is not always better than LightGBM
- GPT-4 is not always better than a fine-tuned smaller model
- Always benchmark multiple approaches on YOUR data
- **Application**: always run baseline comparisons, don't assume

### Occam's Razor for Models
"Prefer the simplest model that explains the data."
- Logistic regression before neural network
- Decision tree before ensemble before deep learning
- Simpler models: faster training, easier debugging, more interpretable, less overfitting
- Complex model justified ONLY when simpler model provably underperforms

### The Bitter Lesson (Rich Sutton)
"General methods leveraging computation scale better than methods leveraging human knowledge."
- Scaling data + compute wins long-term over clever engineering
- But: for production ML with budget constraints, clever engineering still matters
- **Application**: invest in data quality and infrastructure, not just model architecture

### Garbage In, Garbage Out (GIGO)
"Model quality is bounded by data quality."
- Spend 80% of effort on data, 20% on model
- Clean data > clever algorithm every time
- Data bugs are harder to find than code bugs

## Data Quality Laws

### Data Quality Dimensions
1. **Completeness**: no missing critical fields
2. **Accuracy**: values reflect reality
3. **Consistency**: same data, same format everywhere
4. **Timeliness**: data is current enough for the use case
5. **Uniqueness**: no unwanted duplicates
6. **Validity**: values conform to expected schema/range

### Data Leakage Prevention
"When information from outside the training dataset leaks into the model."
- Time-series: NEVER shuffle, split chronologically
- Target leakage: features that encode the label (e.g., "days_since_purchase" in churn prediction)
- Train/test contamination: preprocessing (scaling, encoding) must fit on train only
- **Application**: always split BEFORE any preprocessing

### Feature Engineering Laws
- Features from domain knowledge > automated feature generation
- Interaction features: multiply/ratio related features
- Time-based features: day_of_week, hour, recency, frequency
- Text features: TF-IDF, embeddings, length, keyword presence
- Remove features with near-zero variance or near-perfect correlation

## MLOps Lifecycle

### CRISP-DM Methodology
1. **Business Understanding**: define the problem in business terms
2. **Data Understanding**: explore, profile, quality assessment
3. **Data Preparation**: clean, transform, feature engineering
4. **Modeling**: train, tune, select
5. **Evaluation**: validate against business metrics (not just ML metrics)
6. **Deployment**: serve, monitor, maintain

### MLOps Maturity Levels
- **Level 0**: manual everything (notebook to production handoff)
- **Level 1**: ML pipeline automation (training automated, serving manual)
- **Level 2**: CI/CD for ML (automated training + testing + deployment + monitoring)
- Target Level 1 minimum, Level 2 for production systems

### Model Versioning & Registry
- Every model: versioned with hyperparameters, metrics, dataset snapshot
- MLflow registry: staging → production → archived lifecycle
- Never overwrite a production model — promote new version alongside
- Rollback plan: previous model version always deployable within minutes

### Model Monitoring & Drift
- **Data drift**: input feature distributions shift over time
- **Concept drift**: relationship between features and target changes
- **Performance drift**: model accuracy degrades
- Monitor: prediction distribution, feature distributions, business KPIs
- Alert on drift → retrain → evaluate → promote or rollback

## LLM Engineering Principles

### Prompt Engineering Laws
1. **Be specific**: vague prompts → vague outputs
2. **Give examples**: few-shot learning drastically improves output quality
3. **Structured output**: specify format (JSON schema, markdown template)
4. **System prompt**: set persona, constraints, output format in system message
5. **Chain of thought**: "Think step by step" improves reasoning
6. **Separate data from instructions**: avoid prompt injection via user input

### RAG (Retrieval Augmented Generation) Principles
- **Chunk size matters**: too small = no context, too large = noise dilution
- **Section-aware chunking** > fixed-size chunking (preserve semantic boundaries)
- **Hybrid search**: BM25 (keyword) + vector (semantic) + cross-encoder reranking
- **Relevance threshold**: don't inject irrelevant chunks (cosine > 0.5 or reranker score)
- **Citation**: always link generated content back to source chunks
- **Evaluation**: Ragas metrics — Context Precision, Context Recall, Faithfulness

### LLM Evaluation Framework
- **DeepEval**: 50+ metrics, deterministic DAG scoring, pytest integration
- **Ragas**: RAG-specific — Context Precision, Recall, Faithfulness, Answer Relevancy
- **Key metrics**: hallucination rate, knowledge retention, conversation completeness
- Test before deploy: run evaluation suite on staging before promoting model/prompt changes

### Cost Control for LLM
- Cache repeated queries (hash prompt → response in Redis, TTL 1 hour)
- Use smallest model that achieves quality threshold (GPT-4o-mini before GPT-4o)
- Limit max_tokens per request
- Monitor cost per request via TensorZero + Langfuse
- Batch non-real-time requests (embeddings, analysis)

### Fine-Tuning Decision Framework
When to fine-tune vs prompt engineer:
- Prompt engineering first (faster, cheaper, reversible)
- Fine-tune when: consistent behavior needed, domain-specific terminology, cost per call matters (smaller model matching larger)
- Don't fine-tune when: < 50 examples, rapidly changing requirements, one-off task

## Responsible AI Principles

### Fairness
- Test for demographic bias in training data and model outputs
- Fairness metrics: demographic parity, equalized odds, calibration across groups
- Matching/allocation systems: track fairness across providers (e.g. Gini coefficient of assignment distribution)

### Transparency
- Log all AI interactions (model, tokens, latency, cost)
- Explainable recommendations: show why a worker was matched
- Users should know when they're interacting with AI

### Robustness
- Adversarial testing: try to break the model with edge-case inputs
- Graceful fallback: if AI fails, rule-based fallback works
- Input validation: sanitize before sending to LLM (prevent injection)

### Privacy
- Don't train on user data without consent
- PII scrubbing before logging AI interactions
- Data retention policies for AI training data

## LLMOps Principles (2025-2026)

Source: Databricks LLMOps, IBM LLMOps, "Complete MLOps/LLMOps Roadmap 2026"

### Core LLMOps Rules
1. **Version everything**: prompts, retrieval configs, guardrails, model combinations — not just model weights
2. **Monitor everything**: latency, cost, quality, hallucination rate, user feedback
3. **Control costs**: set max_tokens, cache repeated queries, use smallest model that meets quality bar
4. **Enforce security**: input sanitization, output filtering, PII detection, prompt injection defense
5. **Build feedback loops**: user ratings → fine-tuning data → improved prompts → better outputs

### Production AI Architecture (2026)
Production AI systems are NOT single models. They are complex orchestrations:
- Foundation models + fine-tuned adapters
- Retrieval systems (RAG) + rerankers
- Guardrails (input/output filtering)
- Routing logic (model selection per task)
- Feedback mechanisms (human-in-the-loop)

### LLM-Specific Evaluation Metrics
Beyond traditional ML metrics (accuracy, F1):
- **Perplexity**: model's uncertainty about predictions (lower = better)
- **BLEU/ROUGE**: text generation quality vs reference
- **Human preference ratings**: A/B testing model outputs with humans
- **Semantic similarity scores**: embedding cosine distance to expected output
- **Faithfulness** (Ragas): does the answer use only provided context?
- **Hallucination rate** (DeepEval): frequency of fabricated facts
- **Context precision/recall** (Ragas): is the right context retrieved?

### Experiment Tracking for LLMs
Track more than just hyperparameters:
- Prompt versions (system prompt, few-shot examples)
- Retrieval configurations (chunk size, top-k, reranker model)
- Guardrail settings (input/output filters)
- Model combinations (router → specialist models)
- Use MLflow + Langfuse together: MLflow for model registry, Langfuse for prompt/trace observability
