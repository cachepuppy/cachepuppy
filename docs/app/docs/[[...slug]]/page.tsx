import { getMDXComponents } from "@/components/mdx";
import { source } from "@/lib/source";
import { DocsBody, DocsDescription, DocsPage, DocsTitle } from "fumadocs-ui/layouts/docs/page";
import { createRelativeLink } from "fumadocs-ui/mdx";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import type { ComponentType } from "react";
import type { TOCItemType } from "fumadocs-core/toc";

type DocPageRenderData = {
  body: ComponentType<Record<string, unknown>>;
  toc?: TOCItemType[];
  full?: boolean;
  title: string;
  description?: string;
};

type PageParams = { slug?: string[] };

export default async function Page(props: { params: Promise<PageParams> }) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) {
    notFound();
  }

  const data = page.data as DocPageRenderData;
  const MDX = data.body;

  return (
    <DocsPage toc={data.toc} full={data.full}>
      <DocsTitle>{data.title}</DocsTitle>
      <DocsDescription>{data.description}</DocsDescription>
      <DocsBody>
        <MDX
          components={getMDXComponents({
            a: createRelativeLink(source, page),
          })}
        />
      </DocsBody>
    </DocsPage>
  );
}

export async function generateStaticParams() {
  return source.generateParams();
}

export async function generateMetadata(props: { params: Promise<PageParams> }): Promise<Metadata> {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) {
    notFound();
  }

  const data = page.data as DocPageRenderData;
  return {
    title: data.title,
    description: data.description,
  };
}
