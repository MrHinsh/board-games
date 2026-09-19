package tools

import (
	"encoding/xml"
	"reflect"
	"testing"
)

func TestDirectionalImplementationLinks(t *testing.T) {
	input := `<items><item type="boardgame" id="246900">
<name type="primary" value="Eclipse: Second Dawn for the Galaxy"/>
<link type="boardgameimplementation" id="72125" value="Eclipse: New Dawn for the Galaxy" inbound="true"/>
<link type="boardgameimplementation" id="999999" value="A Future Implementation"/>
<link type="boardgamemechanic" id="2072" value="Dice Rolling"/>
</item></items>`

	var items directionalThingItems
	if err := xml.Unmarshal([]byte(input), &items); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(items.Items) != 1 {
		t.Fatalf("got %d items, want 1", len(items.Items))
	}

	info := extractDirectionalEssentialInfo(items.Items[0])
	if !reflect.DeepEqual(info.Reimplements, []int{72125}) {
		t.Fatalf("reimplements = %v, want [72125]", info.Reimplements)
	}
	if !reflect.DeepEqual(info.ReimplementedBy, []int{999999}) {
		t.Fatalf("reimplemented_by = %v, want [999999]", info.ReimplementedBy)
	}
	if !reflect.DeepEqual(info.Mechanics, []string{"Dice Rolling"}) {
		t.Fatalf("mechanics = %v, want [Dice Rolling]", info.Mechanics)
	}
}
