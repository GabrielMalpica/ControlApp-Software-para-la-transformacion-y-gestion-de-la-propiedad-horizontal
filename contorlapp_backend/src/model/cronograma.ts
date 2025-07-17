import { Conjunto } from "./Conjunto";
import { Tarea } from "./Tarea";

export class Cronograma {
  conjunto: Conjunto;
  tareas: Tarea[];

  constructor(conjunto: Conjunto) {
    this.conjunto = conjunto;
    this.tareas = [];
  }
}
