import { atom, useAtom, useAtomValue, useSetAtom } from 'jotai';
import { Call } from '../../typings';
import { isEnvBrowser } from '../../utils/misc';

const DEBUG_CALLS: Call[] = [
  {
    id: 1,
    info: {
      time: Date.now(),
      location: 'Somewhere',
    },
    coords: [350, 350],
    completed: false,
    linked: false,
    offense: {
      label: 'Bank robbery',
      code: '10-29',
    },
    units: [
      { name: 'Unit 1', type: 'car', members: [{ name: 'Billy bob', callSign: 132 }], id: 1 },
      { name: 'Unit 6', type: 'heli', members: [{ name: 'Someone', callSign: 823 }], id: 2 },
    ],
  },
  {
    id: 2,
    info: {
      time: Date.now(),
      location: 'Somewhere',
    },
    coords: [255, 150],
    completed: true,
    linked: false,
    offense: {
      label: 'Officer Down',
      code: '10-13',
    },
    units: [
      { name: 'Unit 1', type: 'car', members: [{ name: 'Billy bob', callSign: 132 }], id: 1 },
      { name: 'Unit 6', type: 'heli', members: [{ name: 'Someone', callSign: 823 }], id: 2 },
      { name: 'Unit 4', type: 'motor', members: [{ name: 'Someone', callSign: 823 }], id: 3 },
      { name: 'Unit 3', type: 'boat', members: [{ name: 'Someone', callSign: 823 }], id: 4 },
    ],
  },
];

const callTypeAtom = atom<'active' | 'completed'>('active');
export const useCallTypeState = () => useAtom(callTypeAtom);

const callsAtom = atom<Call[]>(isEnvBrowser() ? DEBUG_CALLS : []);
const filteredCallsAtom = atom((get) => {
  const callType = get(callTypeAtom);

  return get(callsAtom).filter((call) => (callType === 'active' ? !call.completed : call.completed));
});

export const useFilteredCalls = () => useAtomValue(filteredCallsAtom);
export const useSetCalls = () => useSetAtom(callsAtom);