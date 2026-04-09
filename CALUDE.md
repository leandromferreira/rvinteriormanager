# PROJECT RV Interior — Contexto Técnico

Mod para Project Zomboid (Build 42) que simula interiores funcionais para veículos (vans, ônibus, RVs, trailers).

## Arquivos principais

| Arquivo | Função |
|---|---|
| `/home/leandro/.steam/debian-installation/steamapps/workshop/content/108600/3543229299/mods/modPROJECTRVInterior/42/media/lua/shared/RVVehicleTypes.lua` | Tipos de veículos suportados e definição das salas |
| `/home/leandro/.steam/debian-installation/steamapps/workshop/content/108600/3543229299/mods/modPROJECTRVInterior/42/media/lua/shared/RVSandbox.lua` | Adiciona veículos customizados via opções de sandbox |
| `/home/leandro/.steam/debian-installation/steamapps/workshop/content/108600/3543229299/mods/modPROJECTRVInterior/42/media/lua/client/RVClientSP.lua` | Lógica completa para Single Player |
| `/home/leandro/.steam/debian-installation/steamapps/workshop/content/108600/3543229299/mods/modPROJECTRVInterior/42/media/lua/client/RVClientMP_V3.lua` | Lógica do cliente para Multiplayer |
| `/home/leandro/.steam/debian-installation/steamapps/workshop/content/108600/3543229299/mods/modPROJECTRVInterior/42/media/lua/server/RVServerMP_V3.lua` | Lógica do servidor para Multiplayer |

## Como funciona o teleporte

O mod mantém salas físicas fixas no mapa em coordenadas distantes (X > 22560, Y > 12000), longe do mapa jogável. Quando o jogador entra num veículo compatível, é teleportado para uma dessas salas.

### Tipos de salas

Cada tipo tem **38 salas disponíveis** (colunas 0–37, espaçadas 60 tiles):

```lua
for col = 0, 37 do table.insert(t, { x = col * 60 + 22560, y = 12060, z = 0 }) end
```

| Tipo | Dimensão | Y base |
|---|---|---|
| `normal` | 2x3 | 12060 |
| `bus` | 3x7 | 12120 |
| `small` | 2x2 | 12180 |
| `3x2caravan` | 3x2 | 12240 |
| `3x6caravan` | 3x6 | 12300 |
| `3x7empty` | 3x7 | 12360 |
| `4x12colossal` | 4x12 | 12420 |

### Identificação de veículos

O mod gera um ID próprio via `ZombRand(1, 99999999)` salvo em `vehicle:getModData().projectRV_uniqueId`. **Não é o mesmo** que o `vehicle:getId()` do engine (PRIMARY KEY no `vehicles.db`).

### Mapeamento veículo → sala

Salvo em `ModData.getOrCreate("modPROJECTRVInterior")`:

```
modData.AssignedRooms[vehicleId]       = { x, y, z }  -- tipo "normal"
modData.AssignedRoomsbus[vehicleId]    = { x, y, z }  -- tipo "bus"
modData.AssignedRooms3x6caravan[...]   = { x, y, z }  -- etc.
modData.Vehicles[vehicleId]            = { x, y, z }  -- posição real do veículo no mundo
modData.Players[playerId]              = { ActualRoom, VehicleId, Seat, RoomType }
modData.batteries[vehicleId]           = { condition, charge }
```

O link veículo→sala é **permanente** — uma vez criado, nunca muda. Salas livres são sorteadas aleatoriamente entre as não ocupadas.

### Verificação de ativação (`loop` / `check`)

O mod só funciona se `check == true`. A função `loop()` (chamada em `OnInitWorld`) itera os mods ativos, extrai dígitos do nome, faz divisões sequenciais e compara com `intOffset = {2, 0.000002288818359375, 0.000001071673525377229}`. Se bater, `check = true`. É uma verificação de licença/dependência.

### Bateria ↔ Gerador

Ao entrar no interior, a bateria do veículo é lida e transferida para o gerador da sala:
```lua
generator:setFuel(batteryCharge * 10)
generator:setActivated(batteryCharge * 100 > 35)  -- liga se bateria > 35%
```

### SP vs MP

- **SP**: toda lógica roda no cliente (`if isServer() or isClient() then return end`)
- **MP**: cliente envia `sendClientCommand("RVServer", "enterRV"/"exitRV")`, servidor processa e responde com `sendServerCommand("RVClient", "teleportToRoom"/"teleportToVehicle")`

---

## Como o PZ salva veículos internamente (Java/Engine)

### vehicles.db — SQLite

```sql
CREATE TABLE vehicles (
    id           INTEGER PRIMARY KEY,  -- sqlId gerado pelo engine, diferente do projectRV_uniqueId
    wx           INTEGER,              -- chunk X
    wy           INTEGER,              -- chunk Y
    x            FLOAT,               -- posição X
    y            FLOAT,               -- posição Y
    worldversion INTEGER,
    data         BLOB                 -- ByteBuffer com TODO o estado do veículo
);
```

### Classe responsável: `zombie.vehicles.VehiclesDB2`

Arquitetura com duas threads:
- **MainThread**: processa fila de operações, serializa veículos (`vehicle.save(ByteBuffer)`) na main thread
- **WorldStreamerThread**: executa I/O no SQLite em thread separada (assíncrona, não bloqueia ninguém)

### Quando o DB é atualizado

O PZ usa estratégia **event-driven** — não atualiza continuamente:

| Evento | Código |
|---|---|
| Jogador **entra** no carro | `BaseVehicle.enter()` → `updateVehicleAndTrailer()` |
| Jogador **sai** do carro | `BaseVehicle.exit()` → `updateVehicleAndTrailer()` |
| Jogador **desconecta** (MP) | `GameServer.disconnectPlayer()` → `updateVehicleAndTrailer()` |
| Chunk **descarregado** | `WorldStreamerThread.unloadChunk()` → itera todos veículos do chunk |
| Thread background (MP) | `SPVThread` chama `updateWorldStreamer()` a cada **500ms** |

Chunk carregado apenas **lê** o DB — nunca escreve ao carregar.

### O que é descarregar um chunk

O mundo é dividido em chunks de 8x8 tiles. O jogo mantém uma grade de chunks ao redor de cada jogador (padrão: 13x13 = 104 tiles de raio). Quando o jogador se afasta, chunks da borda oposta saem da grade — isso é o **unload**. Nesse momento todos os veículos do chunk têm posição gravada no DB.

---

## Sincronização de posição no MP (tempo real)

### UDP a cada frame — `VehiclePhysicsUnreliablePacket`

O cliente que está **dirigindo** é a autoridade física. Envia a cada frame via UDP:
- Posição `x, y, z`
- Rotação (quaternion `qx, qy, qz, qw`)
- Velocidade linear `vx, vy, vz`
- Estado do motor, throttle, rodas

O servidor recebe, atualiza em memória e repassa para outros clientes.  
Outros clientes usam **interpolação** para suavizar o movimento.

O DB **não é atualizado** pelo UDP — só pelos eventos listados acima.

### Atualização de posição no mod (MP)

O cliente envia `sendClientCommand("RVServer", "UpdateVehPos", data)` a cada **180 ticks (~3s)** para manter `modData.Vehicles` atualizado no servidor.

---

## Estratégia recomendada para atualizar posição com menor impacto

**Dirty flag + flush periódico** — só escreve veículos que realmente se moveram:

```lua
-- Checa movimento 1x/segundo (compara floats — custo desprezível)
-- Marca dirty se moveu > 0.5 tile
-- Flush no modData a cada 10s apenas dos dirty
-- Veículos parados nunca geram escrita
```

O custo da escrita no `modData` é apenas Lua em memória — negligenciável comparado à serialização Java do `VehiclesDB2`. O gargalo real seria chamar `VehiclesDB2.updateVehicle()` (não exposto ao Lua), pois serializa ~32KB por veículo na main thread.

---

## Verificar salas disponíveis

```lua
local modData = ModData.getOrCreate("modPROJECTRVInterior")
for typeKey, typeDef in pairs(VehicleTypes) do
    local assignedKey = (typeKey == "normal") and "AssignedRooms" or ("AssignedRooms" .. typeKey)
    local assigned = modData[assignedKey] or {}
    local ocupadas = 0
    for _ in pairs(assigned) do ocupadas = ocupadas + 1 end
    print(typeKey .. ": " .. (#typeDef.rooms - ocupadas) .. "/" .. #typeDef.rooms .. " livres")
end
```

## Desassociar veículo de uma sala

```lua
local modData = ModData.getOrCreate("modPROJECTRVInterior")
local assignedKey = (typeKey == "normal") and "AssignedRooms" or ("AssignedRooms" .. typeKey)
modData[assignedKey][vehicleId] = nil  -- sala fica disponível para outro veículo
```
