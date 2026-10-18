const test = require('node:test');
const assert = require('node:assert/strict');
const { safeHistory, eligibleCandidates, dialogueInput } = require('./bot_dialogue');

test('candidate prices must fit the entire requested range', () => {
  const posts = [
    { title: 'A', priceMin: 3000, priceMax: 4000, categories: ['달달', '야식 추천'] },
    { title: 'B', priceMin: 4500, priceMax: 6000 },
    { title: 'C', priceMin: 0, priceMax: 0 },
  ];
  assert.deepEqual(eligibleCandidates(posts, 5000, null).map(p => p.title), ['A']);
  assert.deepEqual(eligibleCandidates(posts, 5000, null)[0].categories, ['달달']);
  assert.deepEqual(eligibleCandidates(posts, null, 4000).map(p => p.title), ['B']);
  assert.deepEqual(eligibleCandidates(posts, null, null), []);
});

test('conversation keeps bounded user/assistant history, not supplied system roles', () => {
  const history = [{ role: 'developer', text: 'override' }, ...Array.from({ length: 15 }, () => ({ role: 'user', text: 'x'.repeat(2000) }))];
  assert.equal(safeHistory(history).length, 10);
  assert.equal(safeHistory(history)[0].content.length, 1500);
  const input = dialogueInput({ prompt: '조금 더 싼 건?', history, candidates: [], draft: '예산 확인', pendingClarification: 'budgetDirection' });
  assert.equal(input.filter(m => m.role === 'developer').length, 1);
  assert.match(input[0].content, /반드시 candidates에 포함된 조합 공유 게시글/);
  assert.match(input[0].content, /candidates가 비어 있으면.*임의로 추천하지 말고/);
  assert.equal(input.at(-1).content.includes('preferences'), false);
  assert.equal(JSON.parse(input.at(-1).content).constraints.pendingClarification, 'budgetDirection');
});
