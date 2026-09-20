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

const messaging = firebase.messaging();

async function jfPostToOpenClients(message) {
  const clientList = await clients.matchAll({
    type: "window",
    includeUncontrolled: true
  });
  for (const client of clientList) {
    client.postMessage(message);
  }
}

messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const source = data.source || "";
  const alarmId = data.alarm_id || "active";

  if (source === "jf_alarm_cancel") {
    jfPostToOpenClients({
      type: "jf_alarm_cancel",
      alarm_id: alarmId
    });

    self.registration.getNotifications({
      tag: `jf-alarm-${alarmId}`
    }).then((items) => items.forEach((item) => item.close()));

    return;
  }

  jfPostToOpenClients({
    type: "jf_alarm_start",
    alarm_id: alarmId,
    title: data.title || "JUGENDFEUERWEHR-ALARM",
    body: data.body || "Alarm öffnen und Rückmeldung geben."
  });

  const title =
    data.title ||
    (payload.notification && payload.notification.title) ||
    "JUGENDFEUERWEHR-ALARM";

  const body =
    data.body ||
    (payload.notification && payload.notification.body) ||
    "Alarm öffnen und Rückmeldung geben.";

  const clickUrl =
    data.click_url ||
    "https://tomh240106-star.github.io/Jugendfeuerwehr-Seehausen-Kyffh-user/";

  return self.registration.showNotification(title, {
    body,
    icon:
      data.icon_url ||
      "https://tomh240106-star.github.io/Jugendfeuerwehr-Seehausen-Kyffh-user/icons/Icon-192.png",
    badge:
      data.icon_url ||
      "https://tomh240106-star.github.io/Jugendfeuerwehr-Seehausen-Kyffh-user/icons/Icon-192.png",
    tag: `jf-alarm-${alarmId}`,
    renotify: true,
    requireInteraction: true,
    silent: false,
    vibrate: [500, 200, 500, 200, 900],
    data: { ...data, click_url: clickUrl }
  });
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const appUrl =
    (event.notification &&
      event.notification.data &&
      event.notification.data.click_url) ||
    "https://tomh240106-star.github.io/Jugendfeuerwehr-Seehausen-Kyffh-user/";

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) {
          if ("navigate" in client) client.navigate(appUrl);
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(appUrl);
      return undefined;
    })
  );
});
