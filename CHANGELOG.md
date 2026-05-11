# Changelog

## [0.6.1](https://github.com/cachepuppy/cachepuppy/compare/v0.6.0...v0.6.1) (2026-05-11)


### Bug Fixes

* **ci:** use release please token secret ([8f5141b](https://github.com/cachepuppy/cachepuppy/commit/8f5141be662a21f05a9e3a34bfdc7ccfe4590b1e))

## [0.6.0](https://github.com/cachepuppy/cachepuppy/compare/v0.5.0...v0.6.0) (2026-05-11)


### Features

* **ci:** publish sdk and docker on release tags ([86dc541](https://github.com/cachepuppy/cachepuppy/commit/86dc54178d5ffd72a10b4544534688c182ac359a))

## [0.5.0](https://github.com/cachepuppy/cachepuppy/compare/v0.4.0...v0.5.0) (2026-05-10)


### Features

* **api:** add workflow REST endpoints with validated payloads ([6387345](https://github.com/cachepuppy/cachepuppy/commit/638734514439c65c97665bf69e68d663f10292e7))
* **execution:** add stateless step executor with Req and retries ([f621f9a](https://github.com/cachepuppy/cachepuppy/commit/f621f9ae6f86d499a0d0f70c9a1a8ea6fa3ce60d))
* **graph:** add workflow graph diff broadcasting ([d9bbcb7](https://github.com/cachepuppy/cachepuppy/commit/d9bbcb736607329f53884b4dec99106c33088a5a))
* **orchestrator:** add async workflow advancement engine ([46832d9](https://github.com/cachepuppy/cachepuppy/commit/46832d9b3236f2e27483656263a7d357e7fb3716))
* **sdk:** add retryFailedWorkflowSteps and workflows demo scenario 7 ([126d670](https://github.com/cachepuppy/cachepuppy/commit/126d67052e4dcf9d8f28c09f4be7b98fa78becdf))
* Workflow orchestration JS interfaces ([6383ac3](https://github.com/cachepuppy/cachepuppy/commit/6383ac3fa6f9ddf383422157ac75f64d8e50f1f6))
* **workflow:** add deferred failure, retry API, SDK and scenario 6 demo ([737e6c4](https://github.com/cachepuppy/cachepuppy/commit/737e6c42597cd2cd1986d4ab0c2245a2a0cebe92))
* **workflow:** add retry_failed_steps endpoint and tests ([55fa370](https://github.com/cachepuppy/cachepuppy/commit/55fa3709d3218f7e864b281ae88b4aae51d86664))
* **workflow:** add workflow state machine with Horde and ETS snapshots ([3b8aa8f](https://github.com/cachepuppy/cachepuppy/commit/3b8aa8f987ef3070c7b224bf9a9f74d5163ef5a6))
* **workflows:** add clustered workflows demo and realtime graph updates ([59e8817](https://github.com/cachepuppy/cachepuppy/commit/59e881755a4739b942ed3a18f27c4068b659c03c))
* **workflows:** replace branch close with merge-now flow ([88895a5](https://github.com/cachepuppy/cachepuppy/commit/88895a55d4af55b5ddc2bb80c5b59d472fe66824))


### Bug Fixes

* Added dynamic parallel grouping and group identification ([af3f123](https://github.com/cachepuppy/cachepuppy/commit/af3f1238a925ee85128fc8fde9a674209d5b3350))
* Nested branches failing - attempted fix ([594100b](https://github.com/cachepuppy/cachepuppy/commit/594100bd5cc5c574ee2aa10a792c67f3d78c343a))

## [0.4.0](https://github.com/cachepuppy/cachepuppy/compare/v0.3.0...v0.4.0) (2026-05-06)


### Features

* **persistence:** add time-based shard snapshots ([1ea7f14](https://github.com/cachepuppy/cachepuppy/commit/1ea7f14a901bcd57b30793c59e05c213cbb3a9f5))


### Performance Improvements

* **persistence:** skip timer snapshot below wal threshold ([b25f257](https://github.com/cachepuppy/cachepuppy/commit/b25f2579f0da59d4e5cb6f3f1bb4af813463ffad))

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
