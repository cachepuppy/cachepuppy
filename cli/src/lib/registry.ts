import { CliError, ExitCode } from "./ui.js";

interface DockerHubTag {
  name: string;
  last_updated?: string;
}

interface DockerHubTagsResponse {
  results: DockerHubTag[];
}

export async function resolveLatestTag(
  imageRepo: string,
  channel: "stable",
): Promise<string> {
  const [namespace, repo] = imageRepo.split("/");
  if (!namespace || !repo) {
    throw new CliError(
      `Invalid image repository "${imageRepo}". Expected <namespace>/<repo>.`,
      ExitCode.ConfigInvalid,
    );
  }

  const url = `https://hub.docker.com/v2/repositories/${namespace}/${repo}/tags?page_size=100`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new CliError(
      `Failed to query Docker Hub tags for ${imageRepo}.`,
      ExitCode.GenericFailure,
    );
  }

  const payload = (await response.json()) as DockerHubTagsResponse;
  const tags = payload.results ?? [];
  if (tags.length === 0) {
    throw new CliError(
      `No tags found for image repository ${imageRepo}.`,
      ExitCode.GenericFailure,
    );
  }

  if (channel === "stable") {
    const shaTags = tags.filter((tag) => tag.name.startsWith("sha-"));
    if (shaTags.length > 0) {
      const latestStable = sortByUpdatedAt(shaTags).at(0);
      if (latestStable) {
        return latestStable.name;
      }
    }
  }

  const latestTag = sortByUpdatedAt(tags).at(0);
  if (!latestTag) {
    throw new CliError(
      `No valid tags found for image repository ${imageRepo}.`,
      ExitCode.GenericFailure,
    );
  }
  return latestTag.name;
}

function sortByUpdatedAt(tags: DockerHubTag[]): DockerHubTag[] {
  return [...tags].sort((a, b) => {
    const aMs = a.last_updated ? Date.parse(a.last_updated) : 0;
    const bMs = b.last_updated ? Date.parse(b.last_updated) : 0;
    return bMs - aMs;
  });
}
