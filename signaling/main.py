import uuid
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

rooms: dict[str, list] = {}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/rooms")
def create_room():
    room_id = str(uuid.uuid4())
    rooms[room_id] = []
    return {"room_id": room_id}


@app.websocket("/rooms/{room_id}")
async def join_room(websocket: WebSocket, room_id: str):
    if room_id not in rooms:
        await websocket.close(code=4004)
        return

    if len(rooms[room_id]) >= 2:
        await websocket.close(code=4003)
        return

    await websocket.accept()
    rooms[room_id].append(websocket)

    try:
        while True:
            message = await websocket.receive_text()
            for other in rooms[room_id]:
                if other is not websocket:
                    await other.send_text(message)
    except WebSocketDisconnect:
        rooms[room_id].remove(websocket)
        if not rooms[room_id]:
            del rooms[room_id]
