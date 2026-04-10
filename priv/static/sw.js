/**
 * Supervised Slices Service Worker
 *
 * This SW is used to provide more robust browser notifications on mobile,
 * allowing notifications to fire via the showNotification API even when
 * the tab might be backgrounded.
 */

self.addEventListener("install", (event) => {
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim())
})

// We could add push event listener here for full Web Push
self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {}
  const title = data.title || "Supervised Slices"
  const options = {
    body: data.body || "Your order has been updated.",
    icon: "/favicon.ico",
    badge: "/favicon.ico",
    data: {
      url: data.url || "/"
    }
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const urlToOpen = event.notification.data.url

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true })
      .then((windowClients) => {
        for (var i = 0; i < windowClients.length; i++) {
          var client = windowClients[i]
          if (client.url === urlToOpen && "focus" in client) {
            return client.focus()
          }
        }
        if (clients.openWindow) {
          return clients.openWindow(urlToOpen)
        }
      })
  )
})
