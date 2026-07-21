package prompts

import (
	"context"
	"fmt"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

func RegisterGameRecommendationsPrompt(s *server.MCPServer) {
	gameRecommendationPrompt := mcp.NewPrompt("game-recommendations",
		mcp.WithPromptDescription("Get personalized board game recommendations based on your BGG collection and preferences"),
		mcp.WithArgument("username",
			mcp.ArgumentDescription("BoardGameGeek username"),
			mcp.RequiredArgument(),
		),
		mcp.WithArgument("currency",
			mcp.ArgumentDescription("Currency for prices (USD, GBP, EUR) - default: USD"),
		),
		mcp.WithArgument("destination",
			mcp.ArgumentDescription("Destination country (US, GB, DE) - default: US"),
		),
	)

	gameRecommendationHandler := func(ctx context.Context, request mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
		username := request.Params.Arguments["username"]
		if username == "" {
			return nil, fmt.Errorf("username is required")
		}

		currency := request.Params.Arguments["currency"]
		if currency == "" {
			currency = "USD"
		}

		destination := request.Params.Arguments["destination"]
		if destination == "" {
			destination = "US"
		}

		return mcp.NewGetPromptResult(
			"Board Game Recommendation Expert",
			[]mcp.PromptMessage{
				mcp.NewPromptMessage(
					mcp.RoleUser,
					mcp.NewTextContent(fmt.Sprintf(`You are a board game recommendation expert. Please provide personalized game recommendations by following these steps:

1. **Get their top-rated games**: Use the bgg-collection tool with username "%s" and filter for their highest-rated games (minrating: 9, maxrating: 10)

2. **Generate recommendations**: For each of their top-rated games, use the bgg-recommender tool to get similar game recommendations. Use the game ID for faster results when available.

3. **Curate the list**: Consolidate the recommendations and present a final list, randomly picking a few games from each category to ensure variety in genres and mechanics.

4. **Get pricing**: For each final recommendation, use the bgg-price tool to get current prices in %s currency for %s destination

5. **Format the response** as shown below:

## 🎲 Your Game Recommendations

Based on your love of [list 2-3 of their top games], here are my recommendations:

### 1. **Brass: Birmingham** (2018)
*Perfect for fans of economic strategy - build industries and rail networks in Industrial Revolution England*
- **Mechanisms**: Network building, Hand management, Economic
- **Complexity**: 3.9/5
- **Best Price**: [$67.99](link)

[Continue for each recommendation...]

**Guidelines:**
- Keep descriptions compelling and focused on why THEY would enjoy it
- Explain the connection to their favorite games (e.g., "Recommended because you love Wingspan")
- Include variety by taking one recommendation per favorite game
- Always include current pricing with links
- Ensure all recommendations are games they don't already own`, username, currency, destination)),
				),
			},
		), nil
	}

	s.AddPrompt(gameRecommendationPrompt, gameRecommendationHandler)
}
