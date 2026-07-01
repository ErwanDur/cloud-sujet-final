## [1.0.2](https://github.com/ErwanDur/cloud-sujet-final/compare/v1.0.1...v1.0.2) (2026-07-01)


### Bug Fixes

* semrel concurency ([b571b41](https://github.com/ErwanDur/cloud-sujet-final/commit/b571b4177a5b82620c2a83823ac7ae39f0e608f2))

## [1.0.1](https://github.com/ErwanDur/cloud-sujet-final/compare/v1.0.0...v1.0.1) (2026-07-01)


### Bug Fixes

* semrel errors ([9e7f744](https://github.com/ErwanDur/cloud-sujet-final/commit/9e7f744c78a446054dca7c2257879e5e980d140c))

# 1.0.0 (2026-07-01)


### Bug Fixes

* **ansible:** pass execution role to lambda module on code update ([df2ab86](https://github.com/ErwanDur/cloud-sujet-final/commit/df2ab86610cd087d77462418ac86936a3388b2c2))
* **ansible:** satisfy ansible-lint (role-prefix vars, command, changed_when) ([f0f7e7b](https://github.com/ErwanDur/cloud-sujet-final/commit/f0f7e7b5b92460f60a63bc102ac2acaac0767e70))
* copy lambda artifacts to terraform dir, checkov before plan, ansible needs terraform ([69f7a24](https://github.com/ErwanDur/cloud-sujet-final/commit/69f7a2456915ffdd45edc7dacb86c150b16c526c))
* correct working-directory for lambda packaging step ([6536359](https://github.com/ErwanDur/cloud-sujet-final/commit/65363597b3ad6b5ad6628e52ecb72afc709f251d))
* manual trigger for action apply && commilint more permissive ([b4c752f](https://github.com/ErwanDur/cloud-sujet-final/commit/b4c752f52bd6f1a4abf0a5ea53a1f89799f4a4bb))
* package handler.zip in CI before terraform plan ([39c43d6](https://github.com/ErwanDur/cloud-sujet-final/commit/39c43d63e863c74dfa492b71602f8f275c62bd4e))
* sesion tagging ([b497194](https://github.com/ErwanDur/cloud-sujet-final/commit/b497194628261e02aac731833ff3501ca3f7a948))
* **terraform:** set lambda timeout 30s and memory 256MB to avoid conversion timeout ([e5e4a13](https://github.com/ErwanDur/cloud-sujet-final/commit/e5e4a13a66c65ded80e869ad2969423668718dc9))


### Features

* add ansible playbook ([af91b4e](https://github.com/ErwanDur/cloud-sujet-final/commit/af91b4efab98999652cf09944e5ae55d87452f8a))
* add github actions ([1eca1de](https://github.com/ErwanDur/cloud-sujet-final/commit/1eca1de52c419926ca8256cd20d27c79c7f75443))
* add lambda function ([98b3245](https://github.com/ErwanDur/cloud-sujet-final/commit/98b32451b780426e09457686f1a60c5eda74152b))
* **ci:** add semantic-release on lambda function ([5f8a164](https://github.com/ErwanDur/cloud-sujet-final/commit/5f8a1647da7c31b3702193a90da483222960c618))
* deploy terraform modules ([02f9194](https://github.com/ErwanDur/cloud-sujet-final/commit/02f919407be3b05d22afe0937f882d67f89e7209))
* init precommit ([fdb9241](https://github.com/ErwanDur/cloud-sujet-final/commit/fdb92419c76efd643575161402fc321ae91ac5f5))
* **lambda:** rename output file with timestamp on conversion ([30e4ce1](https://github.com/ErwanDur/cloud-sujet-final/commit/30e4ce10b41476f83581dee8808a259f88380584))
