package tools

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"time"

	"github.com/kkjdaniel/gogeek/v2"
	"github.com/kkjdaniel/gogeek/v2/collection"
	"github.com/kkjdaniel/gogeek/v2/constants"
	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

type rawCollectionResponse struct {
	XMLName xml.Name            `xml:"items"`
	Items   []rawCollectionItem `xml:"item"`
}

type rawCollectionItem struct {
	ObjectType    string              `xml:"objecttype,attr" json:"objecttype"`
	ObjectID      int                 `xml:"objectid,attr" json:"objectid"`
	Subtype       string              `xml:"subtype,attr" json:"subtype"`
	CollectionID  int                 `xml:"collid,attr" json:"collid"`
	Name          string              `xml:"name" json:"name"`
	YearPublished int                 `xml:"yearpublished" json:"yearpublished"`
	Image         string              `xml:"image" json:"image"`
	Thumbnail     string              `xml:"thumbnail" json:"thumbnail"`
	Stats         *rawCollectionStats `xml:"stats" json:"-"`
	Status        rawCollectionStatus `xml:"status" json:"status"`
	NumPlays      int                 `xml:"numplays" json:"numplays"`
	Comment       string              `xml:"comment" json:"comment"`
}

type rawCollectionStats struct {
	Rating rawCollectionRating `xml:"rating"`
}

type rawCollectionRating struct {
	Value string `xml:"value,attr"`
}

type rawCollectionStatus struct {
	Own          int    `xml:"own,attr" json:"own"`
	PrevOwned    int    `xml:"prevowned,attr" json:"prevowned"`
	ForTrade     int    `xml:"fortrade,attr" json:"fortrade"`
	Want         int    `xml:"want,attr" json:"want"`
	WantToPlay   int    `xml:"wanttoplay,attr" json:"wanttoplay"`
	WantToBuy    int    `xml:"wanttobuy,attr" json:"wanttobuy"`
	Wishlist     int    `xml:"wishlist,attr" json:"wishlist"`
	Preordered   int    `xml:"preordered,attr" json:"preordered"`
	LastModified string `xml:"lastmodified,attr" json:"lastmodified"`
}

type collectionExportItem struct {
	ObjectType    string              `json:"objecttype"`
	ObjectID      int                 `json:"objectid"`
	Subtype       string              `json:"subtype"`
	CollectionID  int                 `json:"collid"`
	Name          string              `json:"name"`
	YearPublished int                 `json:"yearpublished"`
	Image         string              `json:"image"`
	Thumbnail     string              `json:"thumbnail"`
	Rating        float64             `json:"rating,omitempty"`
	Status        rawCollectionStatus `json:"status"`
	NumPlays      int                 `json:"numplays"`
	Comment       string              `json:"comment"`
}

func CollectionTool(client *gogeek.Client) (mcp.Tool, server.ToolHandlerFunc) {
	tool := mcp.NewTool("bgg-collection",
		mcp.WithDescription("Query a user's board game collection on BoardGameGeek (BGG). Returns all matching games by default with basic info (name, ID, rating, plays, status). Use the filter parameters to narrow results (e.g. owned, wishlist, rated, play count). For detailed information about specific games (description, mechanics, player count, complexity, etc.), follow up with bgg-details using the game IDs from the results."),
		mcp.WithString("username",
			mcp.Required(),
			mcp.Description("The username of the BoardGameGeek (BGG) user who owns the collection. When the user refers to themselves (me, my, I), use 'SELF' as the value."),
		),
		mcp.WithString("subtype",
			mcp.Enum("boardgame", "boardgameexpansion"),
			mcp.Description("Filter by game type: 'boardgame' for base games only (excludes expansions), 'boardgameexpansion' for expansions only"),
		),
		mcp.WithBoolean("owned",
			mcp.Description("Filters for owned games in the collection (default: true if no ownership filters specified)"),
		),
		mcp.WithBoolean("wishlist",
			mcp.Description("Filters for wishlisted games in the collection"),
		),
		mcp.WithBoolean("preordered",
			mcp.Description("Filters for preordered games in the collection"),
		),
		mcp.WithBoolean("fortrade",
			mcp.Description("Filters for games that are marked for trade in the collection"),
		),
		mcp.WithBoolean("rated",
			mcp.Description("Filters for games that are rated in the collection"),
		),
		mcp.WithBoolean("wanttoplay",
			mcp.Description("Filters for games that the user wants to play in the collection"),
		),
		mcp.WithBoolean("played",
			mcp.Description("Filters for games that have recorded plays in the collection"),
		),
		mcp.WithBoolean("wanttobuy",
			mcp.Description("Filters for games that the user wants to buy in the collection"),
		),
		mcp.WithBoolean("hasparts",
			mcp.Description("Filters for games that have spare parts or not in the collection"),
		),
		mcp.WithNumber("minrating",
			mcp.Description("Filters based on the minimum personal rating of the games in the collection"),
		),
		mcp.WithNumber("maxrating",
			mcp.Description("Filters based on the maximum personal rating of the games in the collection"),
		),
		mcp.WithNumber("minbggrating",
			mcp.Description("Filters based on the minimum global BoardGameGeek (BGG) rating of the games in the collection"),
		),
		mcp.WithNumber("maxbggrating",
			mcp.Description("Filters based on the maximum global BoardGameGeek (BGG) rating of the games in the collection"),
		),
		mcp.WithNumber("minplays",
			mcp.Description("Filters based on the minimum number of plays of the games in the collection"),
		),
		mcp.WithNumber("maxplays",
			mcp.Description("Filters based on the maximum number of plays of the games in the collection"),
		),
	)

	handler := func(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		arguments := request.GetArguments()

		username, ok := arguments["username"].(string)
		if !ok || username == "" {
			return mcp.NewToolResultText("Username is required"), nil
		}

		if username == "SELF" {
			envUsername := os.Getenv("BGG_USERNAME")
			if envUsername == "" {
				return mcp.NewToolResultText("BGG_USERNAME environment variable not set. Either set it or provide your specific username instead of 'SELF'."), nil
			}
			username = envUsername
		}

		items, err := queryCollectionWithStats(client, username, arguments)
		if err != nil {
			return mcp.NewToolResultText(fmt.Sprintf("Error fetching collection: %v", err)), nil
		}

		if len(items) == 0 {
			return mcp.NewToolResultText("No items found in collection with the specified filters"), nil
		}

		out, err := json.Marshal(items)
		if err != nil {
			return mcp.NewToolResultText(fmt.Sprintf("Error formatting results: %v", err)), nil
		}

		return mcp.NewToolResultText(string(out)), nil
	}

	return tool, handler
}

func queryCollectionWithStats(client *gogeek.Client, username string, arguments map[string]interface{}) ([]collectionExportItem, error) {
	params := url.Values{}
	params.Set("username", username)
	params.Set("stats", "1")

	for _, opt := range buildCollectionOptions(arguments) {
		opt(params)
	}

	queryURL := constants.CollectionEndpoint + "?" + params.Encode()

	var result rawCollectionResponse
	body, err := fetchCollectionBody(client, queryURL)
	if err != nil {
		return nil, err
	}

	if err := xml.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	items := make([]collectionExportItem, 0, len(result.Items))
	for _, item := range result.Items {
		rating := 0.0
		if item.Stats != nil {
			rating = parseCollectionRating(item.Stats.Rating.Value)
		}

		items = append(items, collectionExportItem{
			ObjectType:    item.ObjectType,
			ObjectID:      item.ObjectID,
			Subtype:       item.Subtype,
			CollectionID:  item.CollectionID,
			Name:          item.Name,
			YearPublished: item.YearPublished,
			Image:         item.Image,
			Thumbnail:     item.Thumbnail,
			Rating:        rating,
			Status:        item.Status,
			NumPlays:      item.NumPlays,
			Comment:       item.Comment,
		})
	}

	return items, nil
}

func parseCollectionRating(value string) float64 {
	if value == "" || value == "N/A" {
		return 0
	}

	rating, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return 0
	}

	return rating
}

func fetchCollectionBody(client *gogeek.Client, queryURL string) ([]byte, error) {
	for attempt := 0; attempt <= 5; attempt++ {
		client.Limiter().Take()

		req, err := http.NewRequest(http.MethodGet, queryURL, nil)
		if err != nil {
			return nil, err
		}

		switch client.AuthMode() {
		case gogeek.AuthAPIKey:
			req.Header.Set("Authorization", "Bearer "+client.APIKey())
		case gogeek.AuthCookie:
			req.Header.Set("Cookie", client.CookieString())
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return nil, err
		}

		if resp.StatusCode == http.StatusAccepted {
			resp.Body.Close()
			if attempt == 5 {
				return nil, fmt.Errorf("collection request still processing")
			}
			time.Sleep(3 * time.Second)
			continue
		}

		if resp.StatusCode == http.StatusTooManyRequests {
			resp.Body.Close()
			if attempt == 5 {
				return nil, fmt.Errorf("collection request rate limited")
			}

			wait := 5 * time.Second
			if retryAfter := resp.Header.Get("Retry-After"); retryAfter != "" {
				if seconds, err := strconv.Atoi(retryAfter); err == nil && seconds > 0 {
					wait = time.Duration(seconds) * time.Second
				}
			}

			time.Sleep(wait)
			continue
		}

		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
		}

		return io.ReadAll(resp.Body)
	}

	return nil, fmt.Errorf("failed to fetch collection response")
}

func buildCollectionOptions(arguments map[string]interface{}) []collection.CollectionOption {
	var options []collection.CollectionOption

	hasExplicitFilter := false
	for key, value := range arguments {
		if value == nil {
			continue
		}

		if key == "username" || key == "subtype" {
			continue
		}

		hasExplicitFilter = true
		break
	}

	if !hasExplicitFilter {
		options = append(options, collection.WithOwned(true))
	}

	if subtype, ok := arguments["subtype"].(string); ok {
		if subtype == "boardgame" {
			options = append(options, collection.WithSubtype("boardgame"))
			options = append(options, collection.WithExcludeSubtype("boardgameexpansion"))
		} else {
			options = append(options, collection.WithSubtype(subtype))
		}
	}

	booleanFilters := map[string]func(bool) collection.CollectionOption{
		"owned":      collection.WithOwned,
		"wishlist":   collection.WithWishlist,
		"preordered": collection.WithPreordered,
		"fortrade":   collection.WithTrade,
		"rated":      collection.WithRated,
		"wanttoplay": collection.WithWantToPlay,
		"played":     collection.WithPlayed,
		"wanttobuy":  collection.WithWantToBuy,
		"hasparts":   collection.WithHasParts,
	}

	for key, fn := range booleanFilters {
		if val, ok := arguments[key].(bool); ok {
			options = append(options, fn(val))
		}
	}

	numericFilters := map[string]func(float64) collection.CollectionOption{
		"minrating":    collection.WithMinRating,
		"maxrating":    collection.WithMaxRating,
		"minbggrating": collection.WithMinBGGRating,
		"maxbggrating": collection.WithMaxBGGRating,
	}

	for key, fn := range numericFilters {
		if val, ok := arguments[key].(float64); ok {
			options = append(options, fn(val))
		}
	}

	if minplays, ok := arguments["minplays"].(float64); ok {
		options = append(options, collection.WithMinPlays(int(minplays)))
	}

	if maxplays, ok := arguments["maxplays"].(float64); ok {
		options = append(options, collection.WithMaxPlays(int(maxplays)))
	}

	return options
}
