"""Optional local visual check. Uses an isolated browser, synthetic routes and the production CSP."""
import argparse
import asyncio
from pathlib import Path
from urllib.parse import urlsplit

from playwright.async_api import async_playwright


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pages", type=Path)
    parser.add_argument("--screenshots", type=Path)
    args = parser.parse_args()
    pages = sorted(args.pages.glob("template-*.html"))
    assert pages, "没有可检查的网页样本"
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    csp = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(executable_path="/usr/bin/chromium", headless=True,
                                                   args=["--no-sandbox", "--disable-background-networking"])
        try:
            for path in pages:
                for width, height in ((1280, 900), (390, 844)):
                    context = await browser.new_context(viewport={"width": width, "height": height})
                    page = await context.new_page()
                    errors, external = [], []
                    page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)

                    async def route_request(route):
                        url = urlsplit(route.request.url)
                        if url.netloc != "template.test":
                            external.append(route.request.url)
                            await route.abort()
                        elif url.path == "/":
                            await route.fulfill(status=200, content_type="text/html; charset=utf-8",
                                                headers={"Content-Security-Policy": csp}, body=path.read_bytes())
                        else:
                            await route.fulfill(status=204, body="")

                    await context.route("**/*", route_request)
                    await page.goto("http://template.test/", wait_until="load")
                    dimensions = await page.evaluate("""({viewport: innerWidth,
                        document: document.documentElement.scrollWidth,
                        bodyDisplay: getComputedStyle(document.body).display,
                        main: document.querySelector('main').getBoundingClientRect().width})""")
                    assert dimensions["document"] <= dimensions["viewport"] + 1, (path, dimensions)
                    assert dimensions["bodyDisplay"] == "block", (path, dimensions)
                    assert dimensions["main"] >= min(width * 0.8, 900), (path, dimensions)
                    assert await page.locator("h1").count() == 1 and await page.title()
                    for anchor in ("collection", "about"):
                        await page.locator(f'nav a[href="#{anchor}"]').click()
                        assert urlsplit(page.url).fragment == anchor
                    if args.screenshots:
                        await page.evaluate("scrollTo(0, 0)")
                        await page.screenshot(path=str(args.screenshots / f"{path.stem}-{width}.png"), full_page=True)
                    assert not external and not errors, (path, width, external, errors)
                    await context.close()
                    print(f"{path.stem}: {width}px、导航、生产 CSP 与无外部资源通过")
        finally:
            await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
