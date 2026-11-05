import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import Settings
from app.connections import ConnectionManager
from app.m2.identity import TestStaticIdentityProvider
from app.m2.routes import router as m2_router
from app.m2.world import World
from app.routes import router


def create_app(settings: Settings | None = None) -> FastAPI:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    settings = settings or Settings.from_environment()
    world = (
        World(settings, TestStaticIdentityProvider(settings.app_environment)) if settings.m2_enabled else None
    )

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        if world is not None:
            await world.start()
        try:
            yield
        finally:
            if world is not None:
                await world.stop()

    application = FastAPI(title="Tu Tien Online — Local Foundation", version="0.2.0", lifespan=lifespan)
    application.state.settings = settings
    application.state.connections = ConnectionManager(settings)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.allowed_origins),
        allow_credentials=settings.m2_enabled,
        allow_methods=["GET", "POST"] if settings.m2_enabled else ["GET"],
        allow_headers=[],
    )
    application.include_router(router)
    if world is not None:
        application.state.m2_world = world
        application.include_router(m2_router)
    logging.getLogger("tu").setLevel(logging.INFO)
    return application


app = create_app()
