import React from 'react';
import {Composition} from 'remotion';
import {demoDuration, ZarathustraIntro} from './ZarathustraIntro';

export const RemotionRoot: React.FC = () => (
  <Composition
    id="ZarathustraIntro"
    component={ZarathustraIntro}
    durationInFrames={demoDuration}
    fps={30}
    width={1176}
    height={764}
  />
);
