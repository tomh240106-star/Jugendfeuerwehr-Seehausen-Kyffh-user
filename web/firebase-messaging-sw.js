importScripts(
  "https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js"
);
importScripts(
  "https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js"
);

firebase.initializeApp({
  apiKey: "AIzaSyAeoxELG1-LDMC49X4H9YnD1YaaIdrdxCA",
  authDomain: "jugendfeuerwehr-seehausen.firebaseapp.com",
  projectId: "jugendfeuerwehr-seehausen",
  storageBucket: "jugendfeuerwehr-seehausen.firebasestorage.app",
  messagingSenderId: "533422487075",
  appId: "1:533422487075:web:d3e0a970adc728e5e4e396",
  measurementId: "G-9W68CV9FK4"
});

firebase.messaging();

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const appUrl = new URL("../", self.registration.scope).toString();

  event.waitUntil(
    clients
      .matchAll({
        type: "window",
        includeUncontrolled: true
      })
      .then((clientList) => {
        for (const client of clientList) {
          if ("focus" in client) {
            if ("navigate" in client) {
              client.navigate(appUrl);
            }
            return client.focus();
          }
        }

        if (clients.openWindow) {
          return clients.openWindow(appUrl);
        }

        return undefined;
      })
  );
});
