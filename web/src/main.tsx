import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { apiBase } from './config';
import { loadSnapshot } from './content';
import { Root } from './Root';
import './styles/tokens.css';
import './styles/global.css';

const root = document.getElementById('root');
if (!root) throw new Error('Missing #root element');

createRoot(root).render(
  <StrictMode>
    <Root snapshot={loadSnapshot()} apiBase={apiBase()} />
  </StrictMode>,
);
