import { atom, useAtom, useAtomValue, useSetAtom } from 'jotai';
import { Character } from '../typings';
import { isEnvBrowser } from '../utils/misc';

const DEBUG_CHARACTER: Character = {
  stateId: '1993201',
  firstName: 'Svetozar',
  lastName: 'Miletić',
  title: 'LSPD Officer',
  grade: 5,
  callSign: 103,
  group: 'police',
  isDispatch: true,
};

const characterAtom = atom<Character>(
  isEnvBrowser()
    ? DEBUG_CHARACTER
    : {
        stateId: '',
        firstName: '',
        lastName: '',
        title: '',
        grade: 0,
        group: '',
        callSign: 0,
        isDispatch: false,
      }
);

export const useCharacter = () => useAtomValue(characterAtom);
export const useSetCharacter = () => useSetAtom(characterAtom);
export const useCharacterState = () => useAtom(characterAtom);
