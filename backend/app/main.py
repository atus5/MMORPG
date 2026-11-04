import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import Settings
from app.connections import ConnectionManager
from app.routes import router


def create_app(settings: Settings | None = None) -> FastAPI:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    settings = settings or Settings.from_environment()
    application = FastAPI(title="Tu Tien Online — Local Foundation", version="0.1.0")
    application.state.settings = settings
    application.state.connections = ConnectionManager(settings)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.allowed_origins),
        allow_credentials=False,
        allow_methods=["GET"],
        allow_headers=[],
    )
    application.include_router(router)
    logging.getLogger("tu").setLevel(logging.INFO)
    return application


app = create_app()
