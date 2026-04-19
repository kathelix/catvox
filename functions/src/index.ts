import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { getSignedUploadURL } from './signedUrl';
export { analyseVideo } from './analyse';
