# Changelog

## [0.3.0](https://github.com/cachepuppy/cachepuppy/compare/v0.2.0...v0.3.0) (2026-05-04)


### Features

* **cache:** add partial updatedata merge path and WAL persist ([7cde37d](https://github.com/cachepuppy/cachepuppy/commit/7cde37d707357eb2400c223e37615c70a8a637fe))
* **demo:** add update data modal for cache partial merge ([a7e2773](https://github.com/cachepuppy/cachepuppy/commit/a7e2773e40159d3606603fd0f14351ae55e73a57))
* **docs:** add CachePuppy theme, static images, and shared logo ([1bf042d](https://github.com/cachepuppy/cachepuppy/commit/1bf042de1f1829abdde0201537d72700382693ff))
* **sdk:** add updateData and document cache partial update ([8a04946](https://github.com/cachepuppy/cachepuppy/commit/8a0494631d89a18f7bb79118ca32da7876dd9ade))


### Bug Fixes

* **docs:** Converted docs to static rendering ([c5d1487](https://github.com/cachepuppy/cachepuppy/commit/c5d1487e2d860388c1deba279547fac1436272cd))

## [0.2.0](https://github.com/cachepuppy/cachepuppy/compare/v0.1.0...v0.2.0) (2026-05-02)


### Features

* **cache:** add prominent rehydration lifecycle logs ([c6b4686](https://github.com/cachepuppy/cachepuppy/commit/c6b468690d62e6d501954926e439b2f4b3578d38))
* **cache:** add rehydration coordinator and phased shard lifecycle ([091b271](https://github.com/cachepuppy/cachepuppy/commit/091b271f71eb2ca47db1235cc5d365d8f69d2e9d))
* **cli:** single-node Docker runtime with volume ([091308a](https://github.com/cachepuppy/cachepuppy/commit/091308a49b3d04b5117a79c8e94856e0cf299466))


### Bug Fixes

* **cache:** register rehydration coordinator locally per node ([e960934](https://github.com/cachepuppy/cachepuppy/commit/e9609346c5bc1845fe7519e121061c57cd1b7c13))


### Performance Improvements

* **cache:** cache owner_valid for WAL; ETS heir recovery ([8316866](https://github.com/cachepuppy/cachepuppy/commit/83168666bfa9143d1344422ffcb5029855b17262))
