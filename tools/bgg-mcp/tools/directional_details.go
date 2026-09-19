package tools

import (
	"fmt"
	"strings"

	"github.com/kkjdaniel/gogeek/v2"
	"github.com/kkjdaniel/gogeek/v2/constants"
	"github.com/kkjdaniel/gogeek/v2/request"
	"github.com/kkjdaniel/gogeek/v2/thing"
)

// directionalThingItem mirrors the fields used by the details response while
// retaining the inbound attribute on links. GoGeek v2's thing.Link omits it.
type directionalThingItem struct {
	Type          string            `xml:"type,attr"`
	ID            int               `xml:"id,attr"`
	Name          []thing.Name      `xml:"name"`
	Description   string            `xml:"description"`
	YearPublished thing.IntValue    `xml:"yearpublished"`
	MinPlayers    thing.IntValue    `xml:"minplayers"`
	MaxPlayers    thing.IntValue    `xml:"maxplayers"`
	MinPlayTime   thing.IntValue    `xml:"minplaytime"`
	MaxPlayTime   thing.IntValue    `xml:"maxplaytime"`
	MinAge        thing.IntValue    `xml:"minage"`
	Thumbnail     string            `xml:"thumbnail"`
	Image         string            `xml:"image"`
	Links         []DirectionalLink `xml:"link"`
	Statistics    *thing.Statistics `xml:"statistics>ratings"`
}

type directionalThingItems struct {
	Items []directionalThingItem `xml:"item"`
}

func queryDirectionalThings(client *gogeek.Client, ids []int) (*directionalThingItems, error) {
	if len(ids) == 0 {
		return nil, fmt.Errorf("no IDs provided")
	}
	if len(ids) > 20 {
		return nil, fmt.Errorf("too many IDs provided, maximum is 20")
	}

	idStrings := make([]string, len(ids))
	for i, id := range ids {
		idStrings[i] = fmt.Sprintf("%d", id)
	}
	url := fmt.Sprintf("%s?id=%s&stats=1", constants.ThingEndpoint, strings.Join(idStrings, ","))

	var result directionalThingItems
	if err := request.FetchAndUnmarshal(client, url, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

func extractDirectionalEssentialInfo(item directionalThingItem) EssentialGameInfo {
	baseLinks := make([]thing.Link, len(item.Links))
	for i, link := range item.Links {
		baseLinks[i] = thing.Link{Type: link.Type, ID: link.ID, Value: link.Value}
	}
	base := thing.Item{
		Type: item.Type, ID: item.ID, Name: item.Name, Description: item.Description,
		YearPublished: item.YearPublished, MinPlayers: item.MinPlayers, MaxPlayers: item.MaxPlayers,
		MinPlayTime: item.MinPlayTime, MaxPlayTime: item.MaxPlayTime, MinAge: item.MinAge,
		Thumbnail: item.Thumbnail, Image: item.Image, Links: baseLinks, Statistics: item.Statistics,
	}
	info := extractEssentialInfo(base)
	addImplementationLinks(&info, item.Links)
	return info
}

func extractDirectionalEssentialInfoList(items []directionalThingItem) []EssentialGameInfo {
	result := make([]EssentialGameInfo, len(items))
	for i, item := range items {
		result[i] = extractDirectionalEssentialInfo(item)
	}
	return result
}
