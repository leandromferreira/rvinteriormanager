# RV Interior Expansion — Notas do Projeto

## Identidade do mod

- **Nome:** RV Interior Expansion
- **ID:** RVInteriorExpansion
- **Autor:** Caçador
- **Build:** Project Zomboid 42
- **Dependência obrigatória:** PROJECT RV Interior (`PROJECTRVInterior42`)

## O que o mod faz

Expande o sistema de interiores de veículos do mod **PROJECT RV Interior**. Enquanto o mod pai gerencia a lógica de entrar/sair de veículos e define os tipos base (com 38 room slots cada), este mod **registra 72 novos tipos de interior** para veículos que o mod pai não cobre.

## Arquivo principal

`42/media/lua/shared/rvupdate.lua` — único arquivo Lua do mod (3836 linhas).

## Arquitetura

### Padrão de cada tipo

Cada tipo é uma função local `AddTypeToRVInteriorN()` que:

1. Carrega a tabela central do mod pai via `pcall(require, "RVVehicleTypes")`
2. Remove os veículos de qualquer lista existente (evita duplicatas)
3. Registra um novo tipo em `VehicleTypes["nome"]` com:
   - `scripts` — lista de IDs de veículos (`Base.NomeDoVeiculo`)
   - `rooms` — coordenadas X/Y/Z no mapa onde ficam os interiores instanciados
   - `offset` — posição onde o jogador aparece ao entrar
   - `requiresTrunk` / `trunkParts` — qual parte do veículo serve de porta de entrada
   - `genX`, `genY`, `genFloor` — posição do gerador dentro do cômodo
   - `roomWidth`, `roomHeight` — tamanho do cômodo em quadrados do mapa

### Ativação

Todas as 72 funções são registradas no evento `OnInitWorld` (linhas 3766–3837), que roda quando o mundo é iniciado.

```lua
Events.OnInitWorld.Add(AddTypeToRVInterior)
Events.OnInitWorld.Add(AddTypeToRVInterior2)
-- ... até AddTypeToRVInterior72
```

## Números gerais

| Métrica | Valor |
|---|---|
| Funções de tipo | 72 |
| Room slots totais adicionados | 493 |
| Veículos mapeados | 271 |

## Distribuição de rooms por tipo

| Rooms por tipo | Nº de tipos |
|---|---|
| 4 | 47 |
| 6 | 1 |
| 7 | 1 |
| 8 | 11 |
| 12 | 3 |
| 16 | 6 |
| 22 | 2 |
| 28 | 1 |

O pool de rooms define quantos veículos desse tipo podem ter interior ativo simultaneamente no mundo. A maioria dos tipos usa apenas 4 slots.

## Relação com o mod pai

- O mod pai (PROJECT RV Interior) define tipos base com **38 room slots** cada.
- Este mod **não altera** esses slots existentes — apenas adiciona novos tipos com pools próprios.
- A função `removeFromAllLists()` (linhas 5–19) garante que um veículo não apareça em dois tipos ao mesmo tempo.

## Mapa

Os interiores ficam na célula **87x86** do mapa customizado incluído em `common/media/maps/rvupdate/`. As coordenadas dos rooms estão na faixa aproximada de X: 26000–27500, Y: 25800–27500.

## Tipos registrados (resumo)

| Função | Tipo | Veículos principais |
|---|---|---|
| AddTypeToRVInterior | Trailer | TrailerKI5cargoLarge |
| AddTypeToRVInterior2 | Trailer2 | TrailerKI5cargoMedium |
| AddTypeToRVInterior3 | Trailer3 | TrailerKI5cargoSmall |
| AddTypeToRVInterior4 | Trailer4 | TrailerKI5livestock |
| AddTypeToRVInterior5 | Trailer5 | TrailerHome, TrailerHomeExplorer |
| AddTypeToRVInterior6 | Trailer6 | TrailerHomeHartman |
| AddTypeToRVInterior7 | semitrailer | SemiTrailerVan |
| AddTypeToRVInterior8 | semitrailer2 | SemiTrailerVanCattle |
| AddTypeToRVInterior19 | semibox | SemiTruckBox |
| AddTypeToRVInterior32 | ki5bus | 87fordB700school |
| AddTypeToRVInterior33 | ki5truck | 87fordF700box |
| AddTypeToRVInterior35 | ki5stepvan | 85chevyStepVan (29 variantes) |
| AddTypeToRVInterior37 | ki586ford | 86fordE150 (65 variantes) |
| AddTypeToRVInterior44 | Vanillastepvan | StepVan (26 variantes) |
| AddTypeToRVInterior51 | vanillavan | Van (57 variantes) |
| AddTypeToRVInterior58 | 73winne | 73Winnebago |
| AddTypeToRVInterior71 | camptrailer2 | Trailer87Scamp16 |
| AddTypeToRVInterior72 | camptrailer | Trailer87Scamp13 |
| ... | ... | ... |
