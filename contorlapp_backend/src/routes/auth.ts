import { Router } from "express";
import { AuthController } from "../controller/AuthController";
import { authRequired } from "../middlewares/auth.middleware";

const router = Router();
const controller = new AuthController();

router.post("/login", controller.login);
router.get("/me", authRequired, controller.me);

export default router;
