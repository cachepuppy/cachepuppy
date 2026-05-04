import Image from "next/image";
import Logo from "@/public/logo.png";

type SiteLogoProps = {
  priority?: boolean;
  className?: string;
};

export function SiteLogo({ priority, className }: SiteLogoProps) {
  return (
    <Image
      src={Logo}
      alt="CachePuppy"
      height={28}
      className={["h-7 w-auto", className].filter(Boolean).join(" ")}
      priority={priority}
    />
  );
}
