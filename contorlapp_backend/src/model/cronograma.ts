import { Conjunto } from "./conjunto";
import { Tarea } from "./tarea";

export class Cronograma {
  conjunto: Conjunto;
  tareas: Tarea[];

  constructor(conjunto: Conjunto) {
    this.conjunto = conjunto;
    this.tareas = [];
  }
}
