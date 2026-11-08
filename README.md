# azure-webserver

A small nginx web server. Run it locally with Docker, deploy it to Azure Container Apps with Terraform from GitHub Actions.

## Run locally

```sh
docker compose up -d --build   # start, then open http://localhost:8080
docker compose down            # stop
```

## Set up Azure and GitHub (once)

1. Create the GitHub repository, push `main`, and let the first `service` workflow run finish.
2. Make the package public: repository > Packages > package settings > Change visibility. Azure pulls the image anonymously.
3. Run `az login` and `gh auth login`, then `scripts/bootstrap-azure.sh OWNER/REPO`.

The workflow signs in to Azure with OIDC, so no secrets are stored in GitHub.

## Start and stop in Azure

```sh
gh workflow run service -f action=start   # deploys the current main, also use this to update
gh workflow run service -f action=stop    # removes the app, keeps the URL for next start
```

A push to `main` builds, tests and publishes the image. It does not change what is running in Azure until the next `start`.
