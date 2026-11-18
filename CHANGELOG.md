# Changelog

## [0.3.0](https://github.com/saicharanrajana/Vanne/compare/v0.2.0...v0.3.0) (2026-11-18)


### Features

* **search:** add saved color filters ([dcb512c](https://github.com/saicharanrajana/Vanne/commit/dcb512cfd6671cee03dc1146d011ea774aa685f7))
* **settings:** refine theme controls ([66a5a0e](https://github.com/saicharanrajana/Vanne/commit/66a5a0e198789f03895c345427fed86d96a79e3d))


### Bug Fixes

* **a11y:** honor reduced motion preferences ([d4ad8c6](https://github.com/saicharanrajana/Vanne/commit/d4ad8c60f73e119338b7206f7b0ef11e468f3f19))
* **ci:** regenerate plugins when building the release apk ([3bfb3dc](https://github.com/saicharanrajana/Vanne/commit/3bfb3dc8a0d2e9bca493ffde3051086e78e1b06d))
* **client:** isolate auth and validate responses ([eeaf045](https://github.com/saicharanrajana/Vanne/commit/eeaf0456b586d70de1605d335649358c1eaa49e0))
* **downloads:** publish files atomically ([460aed3](https://github.com/saicharanrajana/Vanne/commit/460aed3f703481ff0d3d250c0abf42a0ac9304eb))
* **feed:** refresh results when content policy changes ([044fc67](https://github.com/saicharanrajana/Vanne/commit/044fc6700a622f05d36f40d16729a868a70f7d2f))
* **storage:** handle malformed saved data ([541b2ba](https://github.com/saicharanrajana/Vanne/commit/541b2ba50c90b4ef1145ca670fdd86639c7d8edf))

## [0.2.0](https://github.com/saicharanrajana/Vanne/compare/v0.1.0...v0.2.0) (2026-11-17)


### Features

* **shell:** add a feed filter action binding ([732921c](https://github.com/saicharanrajana/Vanne/commit/732921cb64eb7fd737b09eec46504a65038a2517))
* **shell:** add a feed filter action to the toolbar ([2febe18](https://github.com/saicharanrajana/Vanne/commit/2febe184a22158b48a6539508fffdb0a8d4b7e16))
* **shell:** host the filter action in the navigation toolbar ([43c2387](https://github.com/saicharanrajana/Vanne/commit/43c2387041415a07d4798003e1d92fd412ecb81c))
* **ui:** place filter triggers on browse screens ([a0a4a71](https://github.com/saicharanrajana/Vanne/commit/a0a4a71ce85ddf25d92da79fe0a7c05dd2abe12e))

## 0.1.0 (2026-11-17)


### Features

* **detail:** redesign info sheet with expressive metadata cards, color palette and tags ([5b68660](https://github.com/saicharanrajana/vanne/commit/5b686607ce2809b78f6f40873e858f8123b13bed))
* replace async_wallpaper with system_wallpaper ([d0bb8cb](https://github.com/saicharanrajana/vanne/commit/d0bb8cb095bdc45508edbef9c1ff77bb615eac53))


### Bug Fixes

* **app:** safe controller lifecycles, cancellation and rollbacks ([ad546d2](https://github.com/saicharanrajana/vanne/commit/ad546d20ca77740a31dbbe1e6d65d29ce62e4180))
* **client:** harden transport, caching and error contract ([77132d4](https://github.com/saicharanrajana/vanne/commit/77132d4593d64465d820da2b8e804636f6739d4a))
* **detail:** inline wavy indicator for wallpaper targets and harden prepare cache ([7d0d80e](https://github.com/saicharanrajana/vanne/commit/7d0d80e3924262f779655da4e8409da89fa12cbb))
* keep the cache cleanup timer out of widget tests ([23d7783](https://github.com/saicharanrajana/vanne/commit/23d7783ebdcec6eb560427c71407484968dcc6f1))
* **ui:** working replace-key flow, shared hex parsing ([fa29c4f](https://github.com/saicharanrajana/vanne/commit/fa29c4f48cafd7b939e7a0d1be01f11aaa4c5481))


### Performance Improvements

* **images:** bound decode sizes and enlarge the image cache ([0116743](https://github.com/saicharanrajana/vanne/commit/0116743a424066de501d47009fb90017c8dace62))
