// 离线缓存：第一次打开把页面、图片、字体都存下来，之后没网也能玩（PWA）。
// 改了网页或换了图片，把 VERSION 改个数，用户下次打开会自动换新。
const VERSION = 'fridge-v1';
const FILES = [
  "./",
  "index.html",
  "manifest.webmanifest",
  "icons/icon-192.png",
  "icons/icon-512.png",
  "icons/icon-180.png",
  "css/fridge.css",
  "js/anim.js",
  "js/app.js",
  "js/data.js",
  "js/stage.js",
  "js/ui.js",
  "js/views.js",
  "../assets/fridge/fridge_body.png",
  "../assets/fridge/fridge_body_gloss.png",
  "../assets/fridge/fridge_body_shade.png",
  "../assets/fridge/fridge_door_bottom_in.png",
  "../assets/fridge/fridge_door_bottom_in_gloss.png",
  "../assets/fridge/fridge_door_bottom_in_shade.png",
  "../assets/fridge/fridge_door_bottom_out.png",
  "../assets/fridge/fridge_door_bottom_out_gloss.png",
  "../assets/fridge/fridge_door_bottom_out_shade.png",
  "../assets/fridge/fridge_door_top_in.png",
  "../assets/fridge/fridge_door_top_in_gloss.png",
  "../assets/fridge/fridge_door_top_in_shade.png",
  "../assets/fridge/fridge_door_top_out.png",
  "../assets/fridge/fridge_door_top_out_gloss.png",
  "../assets/fridge/fridge_door_top_out_shade.png",
  "../assets/stickers/apple.png",
  "../assets/stickers/bacon.png",
  "../assets/stickers/banana.png",
  "../assets/stickers/beef.png",
  "../assets/stickers/bell_pepper.png",
  "../assets/stickers/blueberries.png",
  "../assets/stickers/bread.png",
  "../assets/stickers/broccoli.png",
  "../assets/stickers/butter.png",
  "../assets/stickers/carrot.png",
  "../assets/stickers/cheese.png",
  "../assets/stickers/chicken.png",
  "../assets/stickers/cucumber.png",
  "../assets/stickers/eggs.png",
  "../assets/stickers/fish.png",
  "../assets/stickers/frozen_dumplings.png",
  "../assets/stickers/frozen_meat.png",
  "../assets/stickers/glass_jar.png",
  "../assets/stickers/grapes.png",
  "../assets/stickers/ice_cream.png",
  "../assets/stickers/juice.png",
  "../assets/stickers/leftovers.png",
  "../assets/stickers/lettuce.png",
  "../assets/stickers/lunchbox.png",
  "../assets/stickers/milk.png",
  "../assets/stickers/mushroom.png",
  "../assets/stickers/noodles.png",
  "../assets/stickers/onion.png",
  "../assets/stickers/orange.png",
  "../assets/stickers/paper_bag.png",
  "../assets/stickers/potato.png",
  "../assets/stickers/rice.png",
  "../assets/stickers/sauce.png",
  "../assets/stickers/shrimp.png",
  "../assets/stickers/soda.png",
  "../assets/stickers/soup.png",
  "../assets/stickers/strawberry.png",
  "../assets/stickers/tomato.png",
  "../assets/stickers/unknown_food_box.png",
  "../assets/stickers/water.png",
  "../assets/stickers/yogurt.png",
  "../assets/fonts/WoAiWanWeiWeiShouXieTi.ttf",
  "../assets/fonts/ZCOOLKuaiLe-Regular.ttf"
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(caches.match(e.request).then((hit) => hit || fetch(e.request)));
});
