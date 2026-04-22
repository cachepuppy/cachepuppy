import { docs } from "collections/server";
import { loader } from "fumadocs-core/source";
import { icons } from "lucide-react";
import { createElement } from "react";

export const source = loader({
  baseUrl: "/docs",
  source: docs.toFumadocsSource(),
  icon(iconName) {
    if (!iconName) {
      return;
    }
    const Icon = icons[iconName as keyof typeof icons];
    if (!Icon) {
      return;
    }
    return createElement(Icon);
  },
});
