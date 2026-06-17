import { describe, expect, it } from 'vitest';
import { serializeState, deserializeState, type SerdeType } from './serde';
import { defaultState } from './state.svelte';
import type { State } from '$lib/types';

const verifySerde = (state: State, serde?: SerdeType): string => {
  const serialized = serializeState(state, serde);
  const deserialized = deserializeState(serialized);
  expect(deserialized).to.deep.equal(state);
  return serialized;
};

describe('Serde tests', () => {
  it('should serialize and deserialize with default serde', () => {
    expect(verifySerde(defaultState)).toMatchInlineSnapshot(
      `"pako:eNpVjMFqwzAMQH9F6LRC-wM5DNpk66WwHXpa3INolNgstoyjUEaSf5_TbrDpJPHe04RXaRgLbHu5XS0lhXNlAuTZ16VNblBPwwV2u-f5yApeAn_NcHg6CgxWYnSh2zz8wypBOZ1WjUGtC5_LA5X3_i3wDFV9oqgSL3_J-SYzvNTu3eb3_4lNnKvXuqR0B7jFLrkGC00jb9Fz8rSeOK3UoFr2bLDIa8Mtjb0aNGHJWaTwIeJ_yyRjZ7FoqR_yNcaGlCtHXaIfZfkGMGZb2A"`
    );
  });

  it('should serialize and deserialize with base64 serde', () => {
    expect(verifySerde(defaultState, 'base64')).toMatchInlineSnapshot(
      `"base64:eyJjb2RlIjoiZmxvd2NoYXJ0IFREXG4gICAgQVtDaHJpc3RtYXNdIC0tPnxHZXQgbW9uZXl8IEIoR28gc2hvcHBpbmcpXG4gICAgQiAtLT4gQ3tMZXQgbWUgdGhpbmt9XG4gICAgQyAtLT58T25lfCBEW0xhcHRvcF1cbiAgICBDIC0tPnxUd298IEVbaVBob25lXVxuICAgIEMgLS0-fFRocmVlfCBGW0Nhcl1cbiAgIiwiZ3JpZCI6dHJ1ZSwibWVybWFpZCI6IntcbiAgXCJ0aGVtZVwiOiBcImRlZmF1bHRcIlxufSIsInBhblpvb20iOnRydWUsInJvdWdoIjpmYWxzZSwidXBkYXRlRGlhZ3JhbSI6dHJ1ZX0"`
    );
  });

  it('should serialize and deserialize with pako serde', () => {
    expect(verifySerde(defaultState, 'pako')).toMatchInlineSnapshot(
      `"pako:eNpVjMFqwzAMQH9F6LRC-wM5DNpk66WwHXpa3INolNgstoyjUEaSf5_TbrDpJPHe04RXaRgLbHu5XS0lhXNlAuTZ16VNblBPwwV2u-f5yApeAn_NcHg6CgxWYnSh2zz8wypBOZ1WjUGtC5_LA5X3_i3wDFV9oqgSL3_J-SYzvNTu3eb3_4lNnKvXuqR0B7jFLrkGC00jb9Fz8rSeOK3UoFr2bLDIa8Mtjb0aNGHJWaTwIeJ_yyRjZ7FoqR_yNcaGlCtHXaIfZfkGMGZb2A"`
    );
  });

  it('should throw error for unrecognized serde', () => {
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-expect-error
    expect(() => serializeState(defaultState, 'unknown')).toThrowError(
      'Unknown serde type: unknown'
    );
    expect(() => deserializeState('unknown:hello')).toThrowError('Unknown serde type: unknown');
  });
});
