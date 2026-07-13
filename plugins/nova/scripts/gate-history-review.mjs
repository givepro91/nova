#!/usr/bin/env node
// Read-only gate history aggregator for `/learn review`.
// Usage: node gate-history-review.mjs <.nova/gate-history.jsonl>
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const FAILURE_MODES = [
  {
    mode: 'verification-evidence-missing',
    cause: 'Required verification was not run or lacks execution evidence',
    preventive_action: 'Run the exact check and retain its passing output',
    proposal: '완료를 보고하기 전에 요구된 검증 명령을 실제로 실행하고 통과 출력을 확인한다.',
  },
  {
    mode: 'verification-failure-unresolved',
    cause: 'A failed check has no passing rerun',
    preventive_action: 'Fix and rerun the same check to passing',
    proposal: '검증 명령이 실패하면 원인을 수정하고 같은 명령의 통과 재실행을 확인한 후에만 완료로 보고한다.',
  },
  {
    mode: 'requested-scope-omitted',
    cause: 'A requested item was left incomplete',
    preventive_action: 'Map every requested item to implementation and evidence',
    proposal: '완료를 보고하기 전에 모든 요청 항목을 구현 결과와 검증 근거에 대응시켜 누락을 확인한다.',
  },
  {
    mode: 'unrequested-scope-added',
    cause: 'Work exceeded the requested scope',
    preventive_action: 'Stay within scope and ask before expansion',
    proposal: '요청 범위 밖의 변경이 필요하면 구현하기 전에 사용자 승인을 받는다.',
  },
  {
    mode: 'reference-not-found',
    cause: 'A referenced artifact does not exist',
    preventive_action: 'Resolve and inspect the real reference first',
    proposal: '파일·심볼·명령·플래그·경로를 사용하거나 보고하기 전에 실제 존재와 내용을 확인한다.',
  },
  {
    mode: 'ambiguity-not-raised',
    cause: 'A material ambiguity was silently assumed away',
    preventive_action: 'Surface it and get direction',
    proposal: '결과를 바꿀 수 있는 모호함은 임의로 결정하지 말고 사용자에게 알려 방향을 확인한다.',
  },
  {
    mode: 'completion-overstated',
    cause: 'Partial, skipped, or blocked work was overstated',
    preventive_action: 'Report the exact incomplete state',
    proposal: '부분 완료·미수행·차단 상태를 완료로 표현하지 말고 남은 작업과 검증 공백을 정확히 보고한다.',
  },
  {
    mode: 'unclassified',
    cause: 'Cause or prevention is not established',
    preventive_action: 'Observation only',
    proposal: null,
  },
];

const MODE_BY_KEY = new Map(FAILURE_MODES.map((item) => [item.mode, item]));
const FAILURE_STATUSES = new Set(['unverified', 'false']);
const CLAIM_STATUSES = new Set(['confirmed', ...FAILURE_STATUSES]);
const SEVERITIES = new Set(['critical', 'high', 'medium']);
const THRESHOLD = 3;

// Old records have no failure_mode. Infer only when their text contains both
// the fixed cause and its preventive action; otherwise keep them observable.
const LEGACY_INFERENCE = [
  {
    mode: 'verification-failure-unresolved',
    cause: [/(check|test|command|검증|테스트|명령).{0,40}(fail|failed|failing|실패)/, /(fail|failed|failing|실패).{0,40}(check|test|command|검증|테스트|명령)/],
    action: [/(fix|resolve|수정|해결).{0,60}(rerun|재실행|다시 실행)/, /(rerun|재실행|다시 실행).{0,60}(pass|passing|통과)/],
  },
  {
    mode: 'verification-evidence-missing',
    cause: [/(not|never).{0,30}(run|execute)/, /no.{0,30}(execution )?(evidence|output)/, /missing.{0,30}(evidence|output)/, /(미실행|실행하지 않|실행 근거.{0,10}(없|누락)|통과 출력.{0,10}(없|누락))/],
    action: [/(run|execute).{0,60}(exact|check|test|command)/, /(retain|capture|keep|confirm).{0,40}(passing )?(output|result|evidence)/, /(검증|테스트|명령).{0,40}실행.{0,40}(통과|출력|확인)/, /통과.{0,30}(출력|결과).{0,30}(확인|보관)/],
  },
  {
    mode: 'requested-scope-omitted',
    cause: [/(requested|required).{0,50}(omitted|missing|incomplete|not implemented)/, /(요청|요구).{0,50}(누락|미완료|미구현)/],
    action: [/(map|check).{0,40}(every|all).{0,30}(request|requirement)/, /(모든|전체).{0,30}(요청|요구).{0,50}(구현|검증|대응)/],
  },
  {
    mode: 'unrequested-scope-added',
    cause: [/(outside|beyond|exceeded).{0,30}(requested )?scope/, /(요청 )?범위.{0,20}(밖|초과)/],
    action: [/(ask|approval|approve).{0,40}(before|prior).{0,30}(expand|change|implement)/, /(확대|변경|구현).{0,30}(전|먼저).{0,30}(승인|확인|문의)/],
  },
  {
    mode: 'reference-not-found',
    cause: [/(file|symbol|command|flag|path|reference).{0,30}(not found|does not exist|missing)/, /(파일|심볼|명령|플래그|경로|참조).{0,30}(없|미존재|찾을 수 없)/],
    action: [/(resolve|inspect|verify|check).{0,40}(real|actual|exist|reference)/, /(실제|존재).{0,30}(확인|점검|조사)/],
  },
  {
    mode: 'ambiguity-not-raised',
    cause: [/(ambiguity|ambiguous).{0,40}(assumed|silent|not raised)/, /(모호|불명확).{0,40}(가정|임의|묵인)/],
    action: [/(surface|raise|ask).{0,40}(direction|clarif|user)/, /(알리|묻|질문).{0,40}(방향|확인|사용자)/],
  },
  {
    mode: 'completion-overstated',
    cause: [/(partial|skipped|blocked|incomplete).{0,50}(complete|done|overstat)/, /(부분|미수행|차단|미완료).{0,50}(완료|과장)/],
    action: [/(report|state).{0,40}(exact|incomplete|remaining|blocked)/, /(남은|미완료|차단|공백).{0,40}(보고|표현|알리)/],
  },
];

// Legacy promotion is deliberately conservative: cause and prevention must be
// separate clauses, and the prevention clause must have affirmative grammar.
const ACTION_VERBS = 'run|execute|retain|capture|keep|confirm|fix|resolve|rerun|map|check|ask|approve|inspect|verify|surface|raise|report|state';
const AFFIRMATIVE_ENGLISH_ACTION = [
  new RegExp(`^(?:please\\s+)?(?:always\\s+)?(?:${ACTION_VERBS})\\b`),
  new RegExp(`^(?:please\\s+)?(?:you\\s+)?(?:must|should|need to|have to)\\s+(?:always\\s+)?(?:${ACTION_VERBS})\\b`),
  new RegExp(`^(?:please\\s+)?(?:do not|don't)\\s+(?:forget|fail|neglect)\\s+to\\s+(?:${ACTION_VERBS})\\b`),
];
const ENGLISH_CONTRADICTION = /\b(?:never|do not|don't|must not|should not|cannot|can't|avoid|refrain|prohibit|prohibited)\b/;
const AFFIRMATIVE_KOREAN_ACTION = /(?:한다|하라|해야 한다|하세요|하십시오)$/;
const KOREAN_CONTRADICTION = /(?:안\s*된다|않(?:는다|아|도록)|하지\s*(?:말|마|않)|해서는\s*안|하면\s*안|금지|삼가|피하)/;

function isAffirmativeAction({ text, terminator }) {
  if (terminator === '?') return false;
  for (const pattern of AFFIRMATIVE_ENGLISH_ACTION) {
    const match = pattern.exec(text);
    if (match && !ENGLISH_CONTRADICTION.test(text.slice(match[0].length))) return true;
  }
  return AFFIRMATIVE_KOREAN_ACTION.test(text) && !KOREAN_CONTRADICTION.test(text);
}

function splitClauses(text) {
  const normalized = text.replace(/\s+(?:→|->|—)\s+/g, '; ');
  return (normalized.match(/[^.!?;:\n]+[.!?;:]?/g) || []).map((raw) => {
    const value = raw.trim();
    const terminator = /[.!?;:]$/.test(value) ? value.at(-1) : '';
    return { text: terminator ? value.slice(0, -1).trim() : value, terminator };
  }).filter(({ text: clause }) => clause !== '');
}

function inferLegacyMode(claim) {
  const text = claim.claim.toLowerCase().replace(/\s+/g, ' ');
  const clauses = splitClauses(text);
  const matches = LEGACY_INFERENCE.filter(({ cause, action }) => {
    const causeClauses = clauses.flatMap(({ text: clause }, index) => cause.some((pattern) => pattern.test(clause)) ? [index] : []);
    const actionClauses = clauses.flatMap((clause, index) =>
      isAffirmativeAction(clause) && action.some((pattern) => pattern.test(clause.text)) ? [index] : []);
    return causeClauses.some((causeIndex) => actionClauses.some((actionIndex) => actionIndex !== causeIndex));
  });
  return matches.length === 1 ? matches[0].mode : 'unclassified';
}

function normalizeMode(claim) {
  if (Object.prototype.hasOwnProperty.call(claim, 'failure_mode')) {
    return MODE_BY_KEY.has(claim.failure_mode) ? claim.failure_mode : 'unclassified';
  }
  return inferLegacyMode(claim);
}

function displayField(record, key) {
  if (!Object.prototype.hasOwnProperty.call(record, key) || record[key] === null || record[key] === undefined) return 'missing';
  return typeof record[key] === 'string' ? record[key] : JSON.stringify(record[key]);
}

function physicalLines(content) {
  if (content === '') return [];
  const lines = content.split('\n');
  if (lines.at(-1) === '') lines.pop();
  return lines.map((line) => line.endsWith('\r') ? line.slice(0, -1) : line);
}

function isGateRecord(record) {
  return record
    && typeof record === 'object'
    && !Array.isArray(record)
    && typeof record.intent === 'string'
    && record.intent.trim() !== ''
    && (record.verdict === 'PASS' || record.verdict === 'ISSUES')
    && Array.isArray(record.claims)
    && record.claims.every((claim) => claim
      && typeof claim === 'object'
      && !Array.isArray(claim)
      && typeof claim.claim === 'string'
      && claim.claim.trim() !== ''
      && typeof claim.status === 'string'
      && CLAIM_STATUSES.has(claim.status.trim().toLowerCase())
      && (!Object.prototype.hasOwnProperty.call(claim, 'failure_mode') || typeof claim.failure_mode === 'string')
      && typeof claim.evidence === 'string'
      && claim.evidence.trim() !== ''
      && typeof claim.severity === 'string'
      && SEVERITIES.has(claim.severity.trim().toLowerCase()));
}

export function reviewGateHistory(content, source = '.nova/gate-history.jsonl') {
  const aggregates = new Map(FAILURE_MODES.map(({ mode }) => [mode, []]));
  const ignored_lines = [];
  let valid_records = 0;

  physicalLines(content).forEach((line, offset) => {
    const lineNumber = offset + 1;
    if (line.trim() === '') {
      ignored_lines.push({ line: lineNumber, reason: 'blank' });
      return;
    }

    let record;
    try {
      record = JSON.parse(line);
    } catch {
      ignored_lines.push({ line: lineNumber, reason: 'malformed' });
      return;
    }
    if (!isGateRecord(record)) {
      ignored_lines.push({ line: lineNumber, reason: 'invalid-record' });
      return;
    }

    valid_records += 1;
    const indicesByMode = new Map();
    record.claims.forEach((claim, index) => {
      if (!claim || typeof claim !== 'object' || Array.isArray(claim)) return;
      const status = typeof claim.status === 'string' ? claim.status.trim().toLowerCase() : '';
      if (!FAILURE_STATUSES.has(status)) return;
      const mode = normalizeMode(claim);
      const indices = indicesByMode.get(mode) || [];
      indices.push(index + 1);
      indicesByMode.set(mode, indices);
    });

    for (const [mode, claim_indices] of indicesByMode) {
      aggregates.get(mode).push({
        line: lineNumber,
        head: displayField(record, 'head'),
        timestamp: displayField(record, 'timestamp'),
        claim_indices,
      });
    }
  });

  const candidates = [];
  const observations = [];
  for (const definition of FAILURE_MODES) {
    const records = aggregates.get(definition.mode);
    if (records.length === 0) continue;
    const result = {
      id: `gate:${definition.mode}`,
      failure_mode: definition.mode,
      occurrences: records.length,
      cause: definition.cause,
      preventive_action: definition.preventive_action,
      proposal: definition.proposal,
      records,
    };
    if (definition.mode !== 'unclassified' && records.length >= THRESHOLD) candidates.push(result);
    else observations.push(result);
  }

  return {
    version: 1,
    source,
    threshold: THRESHOLD,
    valid_records,
    ignored_lines,
    candidates,
    observations,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const file = process.argv[2];
  if (!file || process.argv.length !== 3) {
    console.error('usage: gate-history-review.mjs <.nova/gate-history.jsonl>');
    process.exit(2);
  }
  try {
    process.stdout.write(`${JSON.stringify(reviewGateHistory(readFileSync(file, 'utf8'), file), null, 2)}\n`);
  } catch (error) {
    console.error(`gate-history-review: ${error.message}`);
    process.exit(1);
  }
}
