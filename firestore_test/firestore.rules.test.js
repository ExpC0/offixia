import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

// A demo project ID guarantees emulator tests can never fall through to the
// production Firebase project, even when a developer has local credentials.
const projectId = 'demo-offixia';
let env;

const orgPath = (orgId) => `organizations/${orgId}`;
const employeePath = (orgId, uid) => `${orgPath(orgId)}/employees/${uid}`;
const chatPath = (orgId, chatId) => `${orgPath(orgId)}/chats/${chatId}`;

function auth(uid, email = `${uid}@example.test`) {
  return env.authenticatedContext(uid, { email }).firestore();
}

function organization(ownerUid, joinCode = 'ABC234') {
  return {
    name: 'Example Company',
    joinCode,
    ownerUid,
    workdayStartMinutes: 480,
    employeeIdPrefix: 'OFX',
    nextEmployeeSeq: 2,
    geofenceMetres: 0,
    createdAt: new Date('2026-01-01T00:00:00Z'),
  };
}

function employee(uid, role = 'employee', active = true, employeeId = 'OFX0002') {
  return {
    employeeId,
    name: uid,
    email: `${uid}@example.test`,
    photoUrl: '',
    role,
    department: '',
    jobTitle: '',
    phone: '',
    managerUid: null,
    active,
    joinedAt: new Date('2026-01-01T00:00:00Z'),
  };
}

async function seedMember(orgId, uid, { role = 'employee', active = true } = {}) {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, employeePath(orgId, uid)), employee(uid, role, active));
    await setDoc(doc(db, `memberships/${uid}`), {
      orgId,
      joinedAt: new Date('2026-01-01T00:00:00Z'),
    });
  });
}

async function seedOrganization(orgId = 'org1', ownerUid = 'owner', code = 'ABC234') {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, orgPath(orgId)), organization(ownerUid, code));
    await setDoc(doc(db, `joinCodes/${code}`), {
      orgId,
      createdAt: new Date('2026-01-01T00:00:00Z'),
    });
  });
  await seedMember(orgId, ownerUid, { role: 'md' });
}

before(async () => {
  const rules = await readFile(new URL('../firestore.rules', import.meta.url), 'utf8');
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules, host: '127.0.0.1', port: 8088 },
  });
});

beforeEach(async () => env.clearFirestore());
after(async () => env?.cleanup());

describe('organization entry boundaries', () => {
  test('creates a founder, employee, membership, and code only as one batch', async () => {
    const db = auth('founder');
    const batch = writeBatch(db);
    batch.set(doc(db, orgPath('new-org')), {
      ...organization('founder', 'NEW234'),
      createdAt: serverTimestamp(),
    });
    batch.set(doc(db, employeePath('new-org', 'founder')), {
      ...employee('founder', 'md', true, 'OFX0001'),
      joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'memberships/founder'), {
      orgId: 'new-org',
      joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'joinCodes/NEW234'), {
      orgId: 'new-org',
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  test('rejects a standalone membership pointer', async () => {
    const db = auth('attacker');
    await assertFails(setDoc(doc(db, 'memberships/attacker'), {
      orgId: 'victim-org',
      joinedAt: serverTimestamp(),
    }));
  });

  test('rejects self-minted MD and employee records without entry proof', async () => {
    await seedOrganization('victim-org');
    for (const role of ['md', 'employee']) {
      const uid = `attacker-${role}`;
      const db = auth(uid);
      const batch = writeBatch(db);
      batch.set(doc(db, employeePath('victim-org', uid)), {
        ...employee(uid, role),
        joinedAt: serverTimestamp(),
      });
      batch.set(doc(db, `memberships/${uid}`), {
        orgId: 'victim-org',
        joinedAt: serverTimestamp(),
      });
      await assertFails(batch.commit());
    }
  });

  test('allows a known code join and advances the staff counter atomically', async () => {
    await seedOrganization();
    const db = auth('joiner');
    const batch = writeBatch(db);
    batch.update(doc(db, orgPath('org1')), { nextEmployeeSeq: 3 });
    batch.set(doc(db, employeePath('org1', 'joiner')), {
      ...employee('joiner'),
      joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'memberships/joiner'), {
      orgId: 'org1',
      joinCode: 'ABC234',
      joinedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  test('allows the real code-join transaction to read the organization first', async () => {
    await seedOrganization();
    const db = auth('transaction-joiner');
    const lookupRef = doc(db, 'joinCodes/ABC234');
    await setDoc(doc(db, 'joinAttempts/transaction-joiner'), {
      orgId: 'org1',
      joinCode: 'ABC234',
      createdAt: serverTimestamp(),
    });

    await assertSucceeds(runTransaction(db, async (tx) => {
      const lookup = await tx.get(lookupRef);
      const orgId = lookup.data().orgId;
      const orgRef = doc(db, orgPath(orgId));
      const org = await tx.get(orgRef);
      const seq = org.data().nextEmployeeSeq;

      tx.update(orgRef, { nextEmployeeSeq: seq + 1 });
      tx.set(doc(db, employeePath(orgId, 'transaction-joiner')), {
        ...employee('transaction-joiner', 'employee', true, 'OFX0002'),
        joinedAt: serverTimestamp(),
      });
      tx.set(doc(db, 'memberships/transaction-joiner'), {
        orgId,
        joinCode: 'ABC234',
        joinedAt: serverTimestamp(),
      });
      tx.delete(doc(db, 'joinAttempts/transaction-joiner'));
    }));
  });

  test('a non-member cannot read an organization without a valid join proof', async () => {
    await seedOrganization();
    const db = auth('outsider');
    await assertFails(getDoc(doc(db, orgPath('org1'))));
    await assertFails(setDoc(doc(db, 'joinAttempts/outsider'), {
      orgId: 'org1',
      joinCode: 'WRONG2',
      createdAt: serverTimestamp(),
    }));
  });

  test('cannot enumerate, create, or squat join codes', async () => {
    await seedOrganization();
    const db = auth('outsider');
    await assertSucceeds(getDoc(doc(db, 'joinCodes/ABC234')));
    await assertFails(getDocs(collection(db, 'joinCodes')));
    await assertFails(setDoc(doc(db, 'joinCodes/EVIL23'), {
      orgId: 'org1',
      createdAt: serverTimestamp(),
    }));
  });

  test('the founder rotates a join code only as one atomic replacement', async () => {
    await seedOrganization();
    const db = auth('owner');
    const batch = writeBatch(db);
    batch.update(doc(db, orgPath('org1')), { joinCode: 'NEW234' });
    batch.delete(doc(db, 'joinCodes/ABC234'));
    batch.set(doc(db, 'joinCodes/NEW234'), {
      orgId: 'org1',
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());

    await assertFails(updateDoc(doc(db, orgPath('org1')), {
      joinCode: 'BAD234',
    }));
  });

  test('accepts only the exact role from the signed-in email invite', async () => {
    await seedOrganization();
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'invites/invitee@example.test'), {
        email: 'invitee@example.test',
        orgId: 'org1',
        orgName: 'Example Company',
        role: 'manager',
        department: 'Sales',
        jobTitle: 'Lead',
        invitedByUid: 'owner',
        invitedByName: 'Owner',
        createdAt: new Date('2026-01-01T00:00:00Z'),
      });
    });

    await assertSucceeds(getDoc(doc(
      auth('invitee', 'invitee@example.test'),
      orgPath('org1'),
    )));

    const makeBatch = (role) => {
      const db = auth('invitee', 'invitee@example.test');
      const batch = writeBatch(db);
      batch.update(doc(db, orgPath('org1')), { nextEmployeeSeq: 3 });
      batch.set(doc(db, employeePath('org1', 'invitee')), {
        ...employee('invitee', role),
        joinedAt: serverTimestamp(),
      });
      batch.set(doc(db, 'memberships/invitee'), {
        orgId: 'org1',
        joinedAt: serverTimestamp(),
      });
      batch.delete(doc(db, 'invites/invitee@example.test'));
      return batch;
    };
    await assertFails(makeBatch('md').commit());
    await assertSucceeds(makeBatch('manager').commit());
  });
});

describe('active membership and common workflows', () => {
  test('a suspended MD cannot read organization data or chats', async () => {
    await seedOrganization();
    await seedMember('org1', 'suspended', { role: 'md', active: false });
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, chatPath('org1', 'group1')), {
        name: 'Private', memberUids: ['suspended'], createdByUid: 'suspended',
      });
      await setDoc(doc(db, `${orgPath('org1')}/announcements/a1`), {
        authorUid: 'owner', text: 'Private',
      });
    });
    const db = auth('suspended');
    await assertFails(getDoc(doc(db, orgPath('org1'))));
    await assertFails(getDoc(doc(db, chatPath('org1', 'group1'))));
    await assertFails(getDoc(doc(db, `${orgPath('org1')}/announcements/a1`)));
  });

  test('check-in can get a missing self record, create it, and read history', async () => {
    await seedOrganization();
    await seedMember('org1', 'worker');
    const db = auth('worker');
    const record = doc(db, `${orgPath('org1')}/attendance/worker_2026-08-08`);
    const missing = await assertSucceeds(getDoc(record));
    assert.equal(missing.exists(), false);
    await assertSucceeds(setDoc(record, {
      uid: 'worker',
      employeeName: 'worker',
      date: '2026-08-08',
      checkInAt: serverTimestamp(),
      checkInLat: null,
      checkInLng: null,
      late: false,
      createdAt: serverTimestamp(),
    }));
    await assertSucceeds(getDocs(query(
      collection(db, `${orgPath('org1')}/attendance`),
      where('uid', '==', 'worker'),
    )));
  });

  test('profile messaging can check a missing DM, create it, and send', async () => {
    await seedOrganization();
    await seedMember('org1', 'alice');
    await seedMember('org1', 'bob');
    const db = auth('alice');
    const chatId = 'dm_alice_bob';
    const chat = doc(db, chatPath('org1', chatId));
    const missing = await assertSucceeds(getDoc(chat));
    assert.equal(missing.exists(), false);
    await assertSucceeds(setDoc(chat, {
      name: '', description: '', memberUids: ['alice', 'bob'],
      createdByUid: 'alice', isDirect: true,
      createdAt: serverTimestamp(), lastMessageAt: serverTimestamp(),
      lastMessage: '', lastSenderName: '', lastSenderUid: '',
    }));
    const batch = writeBatch(db);
    batch.set(doc(collection(db, `${chatPath('org1', chatId)}/messages`)), {
      text: 'Hello', senderUid: 'alice', senderName: 'alice',
      sentAt: serverTimestamp(),
    });
    batch.update(chat, {
      lastMessage: 'Hello', lastMessageAt: serverTimestamp(),
      lastSenderName: 'alice', lastSenderUid: 'alice',
    });
    await assertSucceeds(batch.commit());
  });

  test('leaving a chat removes only the caller', async () => {
    await seedOrganization();
    await seedMember('org1', 'alice');
    await seedMember('org1', 'bob');
    await seedMember('org1', 'carol');
    const seedChat = async () => env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), chatPath('org1', 'group1')), {
        name: 'Group', description: '', memberUids: ['alice', 'bob', 'carol'],
        createdByUid: 'bob', isDirect: false,
      });
    });
    await seedChat();
    const db = auth('alice');
    await assertFails(updateDoc(doc(db, chatPath('org1', 'group1')), {
      memberUids: ['bob'],
    }));
    await assertFails(updateDoc(doc(db, chatPath('org1', 'group1')), {
      memberUids: ['alice'],
    }));
    await assertSucceeds(updateDoc(doc(db, chatPath('org1', 'group1')), {
      memberUids: ['bob', 'carol'],
    }));
  });

  test('the founder can recursively remove signaling they did not join', async () => {
    await seedOrganization();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, `${orgPath('org1')}/calls/call1`), {
        callerUid: 'alice', calleeUid: 'bob', status: 'ended',
      });
      await setDoc(doc(db, `${orgPath('org1')}/calls/call1/callerCandidates/c1`), {
        candidate: 'network metadata', sdpMid: '0', sdpMLineIndex: 0,
      });
    });
    const db = auth('owner');
    const candidate = doc(
      db,
      `${orgPath('org1')}/calls/call1/callerCandidates/c1`,
    );
    await assertSucceeds(getDoc(candidate));
    await assertSucceeds(deleteDoc(candidate));
    await assertSucceeds(deleteDoc(doc(db, `${orgPath('org1')}/calls/call1`)));
  });

  test('the founder completes owner, membership, code, and org deletion atomically', async () => {
    await seedOrganization();
    await seedMember('org1', 'worker');
    const db = auth('owner');

    const workerBatch = writeBatch(db);
    workerBatch.delete(doc(db, employeePath('org1', 'worker')));
    workerBatch.delete(doc(db, 'memberships/worker'));
    await assertSucceeds(workerBatch.commit());

    const finalBatch = writeBatch(db);
    finalBatch.delete(doc(db, employeePath('org1', 'owner')));
    finalBatch.delete(doc(db, 'memberships/owner'));
    finalBatch.delete(doc(db, 'joinCodes/ABC234'));
    finalBatch.delete(doc(db, orgPath('org1')));
    await assertSucceeds(finalBatch.commit());
  });
});
